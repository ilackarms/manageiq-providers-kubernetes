class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream
  def initialize(ems)
    @ems = ems
  end

  def start
    @collecting_events = true
  end

  def stop
    @collecting_events = false
  end

  def each_batch
    while @collecting_events
      yield(fetch)
    end
  rescue EOFError => err
    $cn_monitoring_log.info("Monitoring connection closed #{err}")
  end

  def fetch
    unless @current_generation
      @current_generation, @current_index = last_position
    end
    $cn_monitoring_log.info("Fetching alerts. Generation: [#{@current_generation}/#{@current_index}]")
    alert_list, errors = get_messages
    return errors if errors

    # {
    #   "generationID":"323e0863-f501-4896-b7dc-353cf863597d",
    #   "messages":[
    #     "index": 1,
    #     "timestamp": "2017-10-17T08:30:00.466775417Z",
    #     "data": {
    #       "alerts": [
    #         ...
    #       ]
    #     }
    #   ...
    #   ]
    # }
    alerts = []
    alerts << collection_running_event

    @current_generation = alert_list["generationID"]
    return alerts if alert_list['messages'].blank?
    alert_list["messages"].each do |message|
      @current_index = message['index']
      message["data"]["alerts"].each do |alert|
        if alert_for_miq?(alert)
          alerts << process_alert!(alert, @current_generation, @current_index)
        else
          $cn_monitoring_log.info("Skipping alert due to missing annotation or unexpected target")
        end
      end
      @current_index += 1
    end
    $cn_monitoring_log.info("[#{alerts.size}] new alerts. New generation: [#{@current_generation}/#{@current_index}]")
    $cn_monitoring_log.debug(alerts)
    alerts
  end

  def get_messages
    response = @ems.connect.get do |req|
      req.params['generationID'] = @current_generation
      req.params['fromIndex'] = @current_index
    end

    [response.body, nil]
  rescue Faraday::ClientError
    [nil, collection_compromised_event]
  end

  def process_alert!(alert, generation, group_index)
    alert['generationID'] = generation
    alert['index'] = group_index
    alert
  end

  def alert_for_miq?(alert)
    alert.fetch_path("annotations", "miqIgnore").to_s.downcase != "true"
  end

  def last_position
    last_event = @ems.parent_manager.ems_events.where(:source => "DATAWAREHOUSE").last
    last_event ||= OpenStruct.new(:full_data => {})
    last_index = last_event.full_data['index']
    [
      last_event.full_data['generationID'].to_s,
      last_index ? last_index + 1 : 0
    ]
  end

  def collection_compromised_event
    # TODO: Using options for this end is a hack, find a better solution
    @ems.parent_manager.options[:last_collection_problem] ||= Time.zone.now
    @ems.parent_manager.save!
    status_event_common.merge(
      "status" => "firing"
    )
  end

  def collection_running_event
    event = status_event_common.merge(
      "status" => "resolved"
    )
    @ems.parent_manager.options[:last_collection_problem] = nil
    @ems.parent_manager.save!
    event
  end

  def status_event_common
    {
      "annotations" => {
        "url"       => "www.example.com",
        "severity"  => "error",
        "miqTarget" => "ExtManagementSystem",
        "message"   => "Event Collection Problem",
        "UUID"      => "bde8a18c-913c-4b15-ba55-a1ca49b6674f",
      },
      "labels"      => {

      },
      "startsAt"    => @ems.parent_manager.options[:last_collection_problem]
    }
  end
end
