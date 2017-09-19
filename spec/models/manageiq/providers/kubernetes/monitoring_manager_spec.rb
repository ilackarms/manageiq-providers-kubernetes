describe ManageIQ::Providers::Kubernetes::MonitoringManager do
  let(:default_endpoint) { FactoryGirl.create(:endpoint, :role => 'default', :hostname => 'host') }
  let(:default_authentication) { FactoryGirl.create(:authentication, :authtype => 'bearer') }
  let(:prometheus_alerts_endpoint) do
    EvmSpecHelper.local_miq_server(:zone => Zone.seed)
    FactoryGirl.create(
      :endpoint,
      :role       => 'prometheus_alerts',
      :hostname   => 'alerts-prometheus.example.com',
      :port       => 443,
      :verify_ssl => false
    )
  end
  let(:prometheus_authentication) do
    FactoryGirl.create(
      :authentication,
      :authtype => 'prometheus_alerts',
      :auth_key => '_',
    )
  end

  let(:container_manager) do
    FactoryGirl.create(
      :ems_kubernetes,
      :endpoints       => [
        default_endpoint,
        prometheus_alerts_endpoint,
      ],
      :authentications => [
        default_authentication,
        prometheus_authentication,
      ],
    )
  end

  let(:monitoring_manager) { container_manager.monitoring_manager }

  context "#authentication" do
    it "validates authentication with a proper response from message-buffer" do
      VCR.use_cassette(
        described_class.name.underscore,
        # :record => :new_episodes,
      ) do
        expect(monitoring_manager.authentication_status_ok?).to be_falsey
        monitoring_manager.authentication_check_types
        expect(monitoring_manager.authentication_status_ok?).to be_truthy
      end
    end
  end
end
