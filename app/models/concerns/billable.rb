module Billable
  extend ActiveSupport::Concern

  # mixin methods for User and Organization for billing/usage

  # retail hourly rate (dollars)
  OVERAGE_HOURLY_RATE = 22

  def billable_collections
    # assumes every Collection is already assigned an owner.
    # this is done on Collection.create
    Collection.with_deleted.with_role(:owner, self)
  end

  # returns Array of AudioFile records
  def billable_audio_files
    billable_collection_ids = billable_collections.map { |c| c.id.to_s }
    return [] unless billable_collection_ids.size > 0
    items_sql = "select i.id from items as i where i.collection_id in (#{billable_collection_ids.join(',')})"
    audio_files_sql = "select * from audio_files as af where af.duration is not null and af.item_id in (#{items_sql})"
    AudioFile.find_by_sql(audio_files_sql)
  end

  # unlike normal audio_files association, which includes all records the User/Org is authorized to see,
  # my_audio_files limits to only those files where user_id=user.id
  # currently only supports User.
  def my_audio_files
    if self.is_a?(Organization)
      raise "Currently my_audio_files() only available to User class. You called on #{self.inspect}"
    end
    collection_ids = collections.map { |c| c.id.to_s }
    return [] unless collection_ids.size > 0

    items_sql = "select i.id from items as i where i.deleted_at is null and i.collection_id in (#{collection_ids.join(',')})"

    # NOTE we ignore whether duration is set or not. This is different than in transcript_usage definition below.
    audio_files_sql = "select * from audio_files as af where af.deleted_at is null and af.user_id=#{self.id}"
    AudioFile.find_by_sql(audio_files_sql)
  end

  # returns a hash with string values suitable for hstore
  def total_transcripts_report(ttype=:basic)

    # for now, we have only two types. might make sense
    # longer term to store the ttype on the transcriber record.
    case ttype
    when :basic
      usage_type = MonthlyUsage::BASIC_TRANSCRIPT_USAGE
      billable_type = MonthlyUsage::BASIC_TRANSCRIPTS
    when :premium
      usage_type = MonthlyUsage::PREMIUM_TRANSCRIPT_USAGE
      billable_type = MonthlyUsage::PREMIUM_TRANSCRIPTS
    end

    # sum all the monthly usage
    total_secs          = monthly_usages.sum(:value)
    total_billable_secs = monthly_usages.where(use: billable_type).sum(:value)
    total_usage_secs    = monthly_usages.where(use: usage_type).sum(:value)
    total_cost          = monthly_usages.sum(:cost)
    total_retail_cost   = monthly_usages.sum(:retail_cost)
    total_billable_cost = monthly_usages.where(use: billable_type).sum(:cost)
    total_billable_retail_cost = monthly_usages.where(use: billable_type).sum(:retail_cost)
    total_usage_cost    = monthly_usages.where(use: usage_type).sum(:cost)
    total_usage_retail_cost = monthly_usages.where(use: usage_type).sum(:retail_cost)

    # we make seconds and cost fixed-width so that sorting a string works
    # like sorting an integer.
    return { 
      :seconds          => "%010d" % total_secs, 
      :cost             => sprintf('%010.2f', total_cost),
      :retail_cost      => sprintf('%010.2f', total_retail_cost),
      :billable_seconds => "%010d" % total_billable_secs,
      :billable_cost    => sprintf('%010.2f', total_billable_cost),
      :billable_retail_cost => sprintf('%010.2f', total_billable_retail_cost),
      :usage_seconds    => "%010d" % total_usage_secs,
      :usage_cost       => sprintf('%010.2f', total_usage_cost),
      :usage_retail_cost => sprintf('%010.2f', total_usage_retail_cost),
    }
  end

  # returns SQL string for selecting the Transcript objects in the given time period and transcriber
  def sql_for_billable_transcripts_for_month_of(dtim=DateTime.now, transcriber_id)

    # hand-roll sql to optimize query.
    # there might be a way to do this all with activerecord but my activerecord-fu is weak.
    month_start = dtim.utc.beginning_of_month
    month_end = dtim.utc.end_of_month
    start_dtim = month_start.strftime('%Y-%m-%d %H:%M:%S')
    end_dtim   = month_end.strftime('%Y-%m-%d %H:%M:%S')

    billable_collection_ids = billable_collections.map { |c| c.id.to_s }
    return nil unless billable_collection_ids.size > 0

    items_sql = "select i.id from items as i where i.collection_id in (#{billable_collection_ids.join(',')})"
    audio_files_sql = "select af.id from audio_files as af "
    audio_files_sql += "where af.duration is not null "
    audio_files_sql += " and created_at between '#{start_dtim}' and '#{end_dtim}' and af.item_id in (#{items_sql})"
    transcripts_sql = "select * from transcripts as t where t.transcriber_id=#{transcriber_id} and t.audio_file_id in (#{audio_files_sql})"
    transcripts_sql += " order by created_at asc"

    return transcripts_sql
  end

  # unlike total_transcripts_report, transcripts_billable_for_month_of returns hash of numbers not strings.
  def transcripts_billable_for_month_of(dtim=DateTime.now, transcriber_id)
    total_secs = 0
    total_cost = 0
    total_retail_cost = 0

    sql = self.sql_for_billable_transcripts_for_month_of(dtim, transcriber_id)

    # abort early if we have no valid SQL
    return { :seconds => 0, :cost => 0, :retail_cost => 0 } if !sql

    Transcript.find_by_sql(sql).each do |tr|
      af = tr.audio_file_lazarus
      total_secs += tr.billable_seconds(af)
      total_cost += tr.cost(af)
      total_retail_cost += tr.retail_cost(af)
    end

    # cost_per_min is in 1000ths of a dollar, not 100ths (cents)
    # but we round to the nearest penny when we cache it in aggregate.
    return { :seconds => total_secs, :cost => total_cost.fdiv(1000), :retail_cost => total_retail_cost.fdiv(1000) }
  end

  # unlike transcripts_billable_for_month_of, this method looks at usage only, ignoring billable_to.
  # we do, however, pay attention to whether the audio_file is linked directly, so this method is really
  # only useful (at the moment) for User objects.
  def transcripts_usage_for_month_of(dtim=DateTime.now, transcriber_id)
    if self.is_a?(Organization)
      raise "Currently transcripts_usage_for_month_of() only available to User class. You called on #{self.inspect}"
    end
    month_start = dtim.utc.beginning_of_month
    month_end = dtim.utc.end_of_month
    start_dtim = month_start.strftime('%Y-%m-%d %H:%M:%S')
    end_dtim   = month_end.strftime('%Y-%m-%d %H:%M:%S')
    total_secs = 0 
    total_cost = 0 
    total_retail_cost = 0 

    # hand-roll sql to optimize query.
    # there might be a way to do this all with activerecord but my activerecord-fu is weak.
    collection_ids = collections.map { |c| c.id.to_s }

    # abort early if we have no collections
    return { :seconds => 0, :cost => 0, :retail_cost => 0 } if collection_ids.size == 0

    items_sql = "select i.id from items as i where i.collection_id in (#{collection_ids.join(',')})"
    audio_files_sql = "select af.id from audio_files as af "
    audio_files_sql += "where af.duration is not null "
    audio_files_sql += " and af.user_id=#{self.id}"
    audio_files_sql += " and created_at between '#{start_dtim}' and '#{end_dtim}' and af.item_id in (#{items_sql})"
    transcripts_sql = "select * from transcripts as t where t.transcriber_id=#{transcriber_id} and t.audio_file_id in (#{audio_files_sql})"
    Transcript.find_by_sql(transcripts_sql).each do |tr|
      af = tr.audio_file_lazarus
      total_secs += tr.billable_seconds(af)
      total_cost += tr.cost(af)
      total_retail_cost += tr.retail_cost(af)
    end

    # cost_per_min is in 1000ths of a dollar, not 100ths (cents)
    # but we round to the nearest penny when we cache it in aggregate.
    return { :seconds => total_secs, :cost => total_cost.fdiv(1000), :retail_cost => total_retail_cost.fdiv(1000) }
  end 

  def my_audio_file_storage(metered=true)
    total_secs = 0
    my_audio_files.each do |af|
      next unless af.duration
      if af.metered == metered
        total_secs += af.duration
      end
    end
    return total_secs
  end 

  def usage_for(use, now=DateTime.now)
    monthly_usages.where(use: use, year: now.utc.year, month: now.utc.month).sum(:value)
  end 

  def update_usage_for(use, rep, now=DateTime.now)
    monthly_usages.where(use: use, year: now.utc.year, month: now.utc.month).first_or_initialize.update_attributes!(value: rep[:seconds], cost: rep[:cost], retail_cost: rep[:retail_cost])
  end 

  def calculate_monthly_usages!
    months = (DateTime.parse(created_at.to_s)<<1 .. DateTime.now).select{ |d| d.strftime("%Y-%m-01") if d.day.to_i == 1 } 
    months.each do |dtim|
      ucalc = UsageCalculator.new(self, dtim)
      ucalc.calculate(Transcriber.basic, MonthlyUsage::BASIC_TRANSCRIPTS)
      ucalc.calculate(Transcriber.premium, MonthlyUsage::PREMIUM_TRANSCRIPTS)

      # calculate non-billable usage if the current actor is a User in an Org
      if self.is_a?(User) and self.entity != self
        ucalc.calculate(Transcriber.basic, MonthlyUsage::BASIC_TRANSCRIPT_USAGE)
        ucalc.calculate(Transcriber.premium, MonthlyUsage::PREMIUM_TRANSCRIPT_USAGE)
      end
    end 
  end 

  def owns_collection?(coll)
    has_role?(:owner, coll)
  end 

  def transcript_usage_report
    return {
      :basic_seconds => used_basic_transcripts[:seconds],
      :basic_cost => used_basic_transcripts[:cost],
      :basic_billable_seconds => used_basic_transcripts[:billable_seconds],
      :basic_billable_cost => used_basic_transcripts[:billable_cost],
      :basic_usage_seconds => used_basic_transcripts[:usage_seconds],
      :basic_usage_cost => used_basic_transcripts[:usage_cost],
      :premium_seconds => used_premium_transcripts[:seconds],
      :premium_cost => used_premium_transcripts[:cost],
      :premium_billable_seconds => used_premium_transcripts[:billable_seconds],
      :premium_billable_cost => used_premium_transcripts[:billable_cost],
      :premium_usage_seconds => used_premium_transcripts[:usage_seconds],
      :premium_usage_cost => used_premium_transcripts[:usage_cost],
    }   
  end 

  def used_basic_transcripts
    @_used_basic_transcripts ||= total_transcripts_report(:basic)
  end

  def used_premium_transcripts
    @_used_premium_transcripts ||= total_transcripts_report(:premium)
  end

  def get_total_seconds(ttype)
    ttype_s = ttype.to_s
    methname = 'used_' + ttype_s + '_transcripts'
    if transcript_usage_cache.has_key?(ttype_s+'_seconds')
      return transcript_usage_cache[ttype_s+'_seconds'].to_i
    else
      return send(methname)[:seconds].to_i
    end
  end

  def get_total_cost(ttype)
    ttype_s = ttype.to_s
    methname = 'used_' + ttype_s + '_transcripts'
    if transcript_usage_cache.has_key?(ttype_s+'_cost')
      return transcript_usage_cache[ttype_s+'_cost'].to_f
    else
      return send(methname)[:cost].to_f
    end
  end

  # Returns JSON-ready hash of monthly usage, including on-demand charges.
  # NOTE that for the purposes of billing, we ignore the 'cost' and 'retail_cost'
  # of the monthly usage records and instead look at (a) overages and (b) ondemand (premium usage on a basic plan).
  # The one exception is that we use the 'retail_cost' for case (b) since that is derived directly from
  # the transcripts themselves, unlike overages, which use a constant OVERAGE_HOURLY_RATE.
  def usage_summary(now=DateTime.now)
    summary = { 
      this_month: { hours: 0, overage: {}, ondemand: {}, cost: 0.00 },  
      current: [], 
      history: [], 
    }   
    year = now.utc.year
    month = now.utc.month
    thismonth = sprintf("%d-%02d", year, month)
    summary[:this_month][:period] = thismonth
    monthly_usages.order('"yearmonth" desc, "use" asc').each do |mu|
      msum = { 
        period: mu.yearmonth,
        type:   mu.use,
        hours:  mu.value.fdiv(3600).round(3),
        cost:   mu.retail_cost.round(2),  # expose only what we charge customers, whether we charge them or not.
      }
      summary[:history].push msum
      if mu.yearmonth == thismonth
        summary[:current].push msum
      end 
    end 

    # calculate current totals based on the User's plan. This determines overages.
    plan_hours        = plan.hours
    base_monthly_cost = plan.amount  # TODO??
    plan_is_premium   = plan.has_premium_transcripts?

    # if plan is "basic", calculate ondemand premium and overages.
    if !plan_is_premium 
      summary[:current].each do |msum|

        # if there is premium usage, it must be on-demand, so pass on the msum cost. 
        if msum[:type] == MonthlyUsage::PREMIUM_TRANSCRIPTS && msum[:hours] > 0 
          summary[:this_month][:ondemand][:cost]  = msum[:cost]
          summary[:this_month][:ondemand][:hours] = msum[:hours].round(3)
          summary[:this_month][:cost]            += msum[:cost]
          summary[:this_month][:hours]           += msum[:hours].round(3)

        # basic plan, basic usage. 
        elsif msum[:type] == MonthlyUsage::BASIC_TRANSCRIPTS

           # month-to-date hours
           summary[:this_month][:hours] += msum[:hours].round(3)

           # check for overage
           if msum[:hours] > plan_hours
             summary[:this_month][:overage][:hours] = msum[:hours] - plan_hours
             # we do not charge for basic plan overages. instead we just prevent them at upload time.
             #summary[:this_month][:overage][:cost] = (OVERAGE_HOURLY_RATE * summary[:this_month][:overage][:hours]).round(2)
             #summary[:this_month][:cost] += summary[:this_month][:overage][:cost]
           end
        end
      end

    # otherwise, plan is premium. sum this month and check for overages only.
    else
      summary[:current].each do |msum|
        summary[:this_month][:hours] += msum[:hours].round(3)
        summary[:this_month][:cost]  += msum[:cost]

        if msum[:type] == MonthlyUsage::PREMIUM_TRANSCRIPTS
          if msum[:hours] > plan_hours
            summary[:this_month][:overage][:hours] = msum[:hours] - plan_hours
            summary[:this_month][:overage][:cost] = (OVERAGE_HOURLY_RATE * summary[:this_month][:overage][:hours]).round(2)
            summary[:this_month][:cost] += summary[:this_month][:overage][:cost]
          end
        end
      end
    end

    # return
    summary
  end

  def is_over_monthly_limit?
    summ = self.entity.usage_summary
    if summ[:this_month][:overage][:hours].to_f > 0
      return true
    else
      return false
    end
  end

end
