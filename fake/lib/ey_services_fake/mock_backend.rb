module EyServicesFake
  class MockBackend

    def self.tresfiestas_fake
      require 'ey_services_fake/tresfiestas_fake'
      TresfiestasFake
    end

    def self.setup!(actors = {})
      unless actors[:awsm]
        require 'ey_services_fake/reacharound_awsm'
        actors[:awsm] = ReacharoundAwsm.new
      end
      unless actors[:service_provider]
        require 'ey_services_fake/mocking_bird_service'
        actors[:service_provider] = MockingBirdService.new
      end
      unless actors[:tresfiestas]
        actors[:tresfiestas] = tresfiestas_fake.new
      end
      new(actors)
    end

    def app_for(actor_name)
      this = self
      @apps ||= {}
      @apps[actor_name] ||= Rack::Builder.new do
        this.actors.each do |k, actor|
          if actor.respond_to?(:extra_middlewares)
            self.instance_eval(&actor.extra_middlewares)
          end
        end
        if ENV["REQUEST_DEBUG"]
          require 'request_visualizer'
          use RequestVisualizer do |str|
            found = str
            this.actors.each do |k, actor|
              if str.match(actor.base_url)
                found = k.to_s
              end
            end
            found
          end
        end
        run this.actors[actor_name].app
      end
    end

    def app
      this = self
      @app ||= Rack::Builder.new do
        this.actors.each do |k, actor|
          map "#{actor.base_url}/" do
            run this.app_for(k)
          end
        end
      end
    end

    attr_reader :actors
    def initialize(actors)
      @actors = actors
    end

    def actor(role)
      @actors[role] or raise "No actor registered as #{role}, I have #{@actors.keys.inspect}"
    end

    def reset!
      @actors.values.each do |v|
        v.reset!
      end
    end

    def awsm
      awsm_hash = actor(:tresfiestas).find_awsm
      unless awsm_hash
        awsm_hash = actor(:tresfiestas).create_awsm(actor(:awsm).base_url, app_for(:awsm))
        actor(:awsm).setup(awsm_hash[:auth_id], awsm_hash[:auth_key], actor(:tresfiestas).base_url, app_for(:tresfiestas))
      end
      awsm_hash
    end

    def partner
      partner_hash = actor(:tresfiestas).find_partner(sso_user)
      unless partner_hash
        partner_hash = actor(:tresfiestas).create_partner(sso_user, actor(:service_provider).base_url, app_for(:service_provider))
        @actors.values.each do |actor|
          if actor.respond_to?(:service_provider_setup)
            actor.service_provider_setup(partner_hash[:auth_id], partner_hash[:auth_key], actor(:service_provider).base_url, app_for(:service_provider))
          end
        end
        actor(:service_provider).setup(partner_hash[:auth_id], partner_hash[:auth_key], actor(:tresfiestas).base_url, app_for(:tresfiestas))
      end
      partner_hash
    end

    def service
      partner_hash = self.partner
      service_hash = actor(:tresfiestas).find_service(partner_hash[:id])
      unless service_hash
        actor(:service_provider).register_service(partner_hash[:registration_url])
        service_hash = actor(:tresfiestas).find_service(partner_hash[:id])
      end
      if actor(:tresfiestas).respond_to?(:document_service)
        service_hash.merge!(:service_doc => actor(:tresfiestas).document_service(service_hash[:id]))
      end
      service_hash.merge(:partner => partner_hash)
    end

    def sso_user
      awsm
      actor(:awsm).sso_user #allows for nils (some implementations of AWSM may decide this is ok)
    end

    def sso_account
      awsm #need to have setup awsm before you can create accounts!
      sso_user_something = sso_user #the sso_user is a somehting, not necessarily a hash
      sso_account_hash = actor(:awsm).find_sso_account(sso_user_something)
      unless sso_account_hash
        sso_account_hash = actor(:awsm).create_sso_account(sso_user_something)
      end
      sso_account_hash
    end

    def service_enablement
      sso_account_hash = self.sso_account
      service_hash = self.service
      unless actor(:tresfiestas).service_available_for_account?(service_hash[:id], sso_account_hash[:id])
        actor(:tresfiestas).make_service_available_for_account(service_hash[:id], sso_account_hash[:id])
      end
      {
        :service => service_hash,
        :sso_account => sso_account_hash,
      }
    end

    def service_account
      service_enablement_hash = self.service_enablement
      sso_account_hash = service_enablement_hash[:sso_account]
      service_hash = service_enablement_hash[:service]
      service_account_hash = actor(:tresfiestas).find_service_account(service_hash[:id], sso_account_hash[:id])
      unless service_account_hash
        actor(:awsm).enable_service(service_hash[:id], sso_account_hash[:id])
        service_account_hash = actor(:tresfiestas).find_service_account(service_hash[:id], sso_account_hash[:id])
      end
      service_account_hash.merge(:name => sso_account_hash[:name], :service => service_hash, :sso_account => sso_account_hash)
    end

    def destroy_service_account
      actor(:awsm).disable_service(service_account[:id])
    end

    def app_deployment
      app_deployment_hash = actor(:awsm).find_app_deployment(sso_account[:id])
      unless app_deployment_hash
        actor(:awsm).create_app_deployment(sso_account[:id], "myapp", "myenv", "production")
        app_deployment_hash = actor(:awsm).find_app_deployment(sso_account[:id])
      end
      app_deployment_hash
    end

    def provisioned_service
      service_account_hash = self.service_account
      sso_account_hash = service_account_hash[:sso_account]
      app_deployment_hash = self.app_deployment
      provisioned_service_hash = actor(:tresfiestas).find_provisioned_service(service_account_hash[:id], app_deployment_hash[:id])
      unless provisioned_service_hash
        actor(:awsm).provision_service(sso_account_hash[:id], service_account_hash[:id], app_deployment_hash[:id])
        provisioned_service_hash = actor(:tresfiestas).find_provisioned_service(service_account_hash[:id], app_deployment_hash[:id])
      end
      provisioned_service_hash.merge(:service_account => service_account_hash, :app_deployment => app_deployment_hash)
    end

    def destroy_provisioned_service
      actor(:awsm).deprovision_service(provisioned_service[:id])
    end

    def latest_invoice
      actor(:tresfiestas).latest_invoice
    end

    def latest_status_message
      actor(:tresfiestas).latest_status_message
    end

    def send_message(message_url, message_type, message_subject, message_body = nil)
      actor(:service_provider).send_message(message_url, message_type, message_subject, message_body)
    end

    def send_invoice(invoices_url, total_amount_cent, line_item_description)
      actor(:service_provider).send_invoice(invoices_url, total_amount_cent, line_item_description)
    end

    def service_account_sso_url
      configuration_url = service_account[:pushed_service_account][:configuration_url]
      params = {
        'timestamp' => Time.now.iso8601,
        'ey_user_id' => sso_user.id,
        'ey_user_name' => "Person Name",
        'ey_return_to_url' => "https://cloud.engineyard.com/dashboard",
        'access_level' => 'owner',
      }
      EY::ApiHMAC::SSO.sign(configuration_url,
                            params,
                            partner[:auth_id],
                            partner[:auth_key])
    end

  end
end
