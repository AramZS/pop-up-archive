class CallbacksController < ApplicationController

  skip_before_filter :verify_authenticity_token

  def amara
    if params[:event] == "subs-approved" || params[:event] == "subs-new"
      # figure out what task this is related to
      if task = Task.where("extras -> 'video_id' = ?", params[:video_id]).first
        FinishTaskWorker.perform_async(task.id) unless Rails.env.test?
      end
      head 202
    else
      head 200
    end
  end

  def fixer
    @resource = params[:model_name].camelize.constantize.find(params[:id])
    if params[:task].present? && @resource.update_from_fixer(params[:task])
      head 202
    else
      head 200
    end    
  end

  def speechmatics
    @resource = params[:model_name].camelize.constantize.find(params[:id])

    # don't know which param it is going to be
    if job_id = params[:id] || params[:job_id]
      if task = @resource.tasks.speechmatics_transcribe.where("extras -> 'job_id' = ?", job_id)
        FinishTaskWorker.perform_async(task.id) unless Rails.env.test?
      end
      head 202
    else
      head 200
    end    
  
  end

end
