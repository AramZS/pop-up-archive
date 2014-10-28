module Billable
  extend ActiveSupport::Concern

  # mixin methods for User and Organization for billing/usage
  def billable_collections
    Collection.with_role(:owner, self)
  end

  # returns a hash with string values suitable for hstore
  def total_transcripts_report(ttype=:basic)

    # for now, we have only two types. might make sense
    # longer term to store the ttype on the transcriber record.
    case ttype
    when :basic
      use_types = [MonthlyUsage::BASIC_TRANSCRIPTS, MonthlyUsage::BASIC_TRANSCRIPT_USAGE]
    when :premium
      use_types = [MonthlyUsage::PREMIUM_TRANSCRIPTS, MonthlyUsage::PREMIUM_TRANSCRIPT_USAGE]
    end

    # sum all the monthly usage
    total_secs = monthly_usages.where(use: use_types).sum(:value)
    total_cost = monthly_usages.where(use: use_types).sum(:cost)

    # we make seconds and cost fixed-width so that sorting a string works
    # like sorting an integer.
    return { :seconds => "%010d" % total_secs, :cost => sprintf('%010.2f', total_cost) }
  end

  # unlike total_transcripts_report, transcripts_billable_for_month_of returns hash of numbers not strings.
  def transcripts_billable_for_month_of(dtim=DateTime.now, transcriber_id)
    month_start = dtim.utc.beginning_of_month
    month_end = dtim.utc.end_of_month
    start_dtim = month_start.strftime('%Y-%m-%d %H:%M:%S')
    end_dtim   = month_end.strftime('%Y-%m-%d %H:%M:%S')
    total_secs = 0
    total_cost = 0

    # hand-roll sql to optimize query.
    # there might be a way to do this all with activerecord but my activerecord-fu is weak.
    billable_collection_ids = billable_collections.map { |c| c.id.to_s }

    # abort early if we have no billable collections
    return { :seconds => 0, :cost => 0 } if billable_collection_ids.size == 0

    items_sql = "select i.id from items as i where i.deleted_at is null and i.collection_id in (#{billable_collection_ids.join(',')})"
    audio_files_sql = "select af.id from audio_files as af "
    audio_files_sql += "where af.deleted_at is null and af.duration is not null "
    audio_files_sql += " and created_at between '#{start_dtim}' and '#{end_dtim}' and af.item_id in (#{items_sql})"
    transcripts_sql = "select * from transcripts as t where t.transcriber_id=#{transcriber_id} and t.audio_file_id in (#{audio_files_sql})"
    Transcript.find_by_sql(transcripts_sql).each do |tr|
      af = tr.audio_file
      total_secs += tr.billable_seconds(af)
      total_cost += tr.cost(af)
    end

    # cost_per_min is in 1000ths of a dollar, not 100ths (cents)
    # but we round to the nearest penny when we cache it in aggregate.
    return { :seconds => total_secs, :cost => total_cost.fdiv(1000) }
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

    # hand-roll sql to optimize query.
    # there might be a way to do this all with activerecord but my activerecord-fu is weak.
    collection_ids = collections.map { |c| c.id.to_s }

    # abort early if we have no collections
    return { :seconds => 0, :cost => 0 } if collection_ids.size == 0

    items_sql = "select i.id from items as i where i.deleted_at is null and i.collection_id in (#{collection_ids.join(',')})"
    audio_files_sql = "select af.id from audio_files as af "
    audio_files_sql += "where af.deleted_at is null and af.duration is not null "
    audio_files_sql += " and af.user_id=#{self.id}"
    audio_files_sql += " and created_at between '#{start_dtim}' and '#{end_dtim}' and af.item_id in (#{items_sql})"
    transcripts_sql = "select * from transcripts as t where t.transcriber_id=#{transcriber_id} and t.audio_file_id in (#{audio_files_sql})"
    Transcript.find_by_sql(transcripts_sql).each do |tr|
      af = tr.audio_file
      total_secs += tr.billable_seconds(af)
      total_cost += tr.cost(af)
    end

    # cost_per_min is in 1000ths of a dollar, not 100ths (cents)
    # but we round to the nearest penny when we cache it in aggregate.
    return { :seconds => total_secs, :cost => total_cost.fdiv(1000) }
  end 

  def usage_for(use, now=DateTime.now)
    monthly_usages.where(use: use, year: now.utc.year, month: now.utc.month).sum(:value)
  end 

  def update_usage_for(use, rep, now=DateTime.now)
    monthly_usages.where(use: use, year: now.utc.year, month: now.utc.month).first_or_initialize.update_attributes!(value: rep[:seconds], cost: rep[:cost])
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
      :premium_seconds => used_premium_transcripts[:seconds],
      :basic_cost => used_basic_transcripts[:cost],
      :premium_cost => used_premium_transcripts[:cost],
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

end
