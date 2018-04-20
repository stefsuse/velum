# frozen_string_literal: true
require "rails_helper"

# rubocop:disable RSpec/AnyInstance
RSpec.describe SetupController, type: :controller do
  let(:user)   { create(:user)   }
  let(:minion) { create(:minion) }
  let(:settings_params) do
    {
      dashboard:    "dashboard.example.com",
      enable_proxy: "disable"
    }
  end

  before do
    setup_stubbed_pending_minions!
  end

  describe "GET /" do
    it "gets redirected if not logged in" do
      get :welcome
      expect(response.status).to eq 302
    end

    context "previous configure with proxy settings" do
      let(:pillars) do
        {
          dashboard:        "dashboard.example.com",
          http_proxy:       "squid.corp.net:3128",
          https_proxy:      "squid.corp.net:3128",
          no_proxy:         "localhost",
          proxy_systemwide: "true"
        }
      end

      before do
        Pillar.apply(pillars, required_pillars: [:dashboard])

        sign_in user

        get :welcome
      end

      it "assigns @enable_proxy" do
        expect(assigns(:enable_proxy)).to eq(true)
      end

      it "assigns @proxy_systemwide" do
        expect(assigns(:proxy_systemwide)).to eq("true")
      end

      it "assigns @http_proxy" do
        expect(assigns(:http_proxy)).to eq("squid.corp.net:3128")
      end

      it "assigns @https_proxy" do
        expect(assigns(:https_proxy)).to eq("squid.corp.net:3128")
      end

      it "assigns @no_proxy" do
        expect(assigns(:no_proxy)).to eq("localhost")
      end
    end

    context "HTML rendering" do
      before do
        sign_in user

        get :welcome
      end

      it "returns a 200 if logged in" do
        expect(response.status).to eq 200
      end

      it "renders with HTML if no format was specified" do
        expect(response["Content-Type"].include?("text/html")).to be true
      end
    end
  end

  describe "GET /setup/worker-bootstrap via HTML" do
    before do
      sign_in user
      Pillar.create pillar: "dashboard", value: "localhost"
    end

    it "sets @controller_node to dashboard pillar value" do
      get :worker_bootstrap
      expect(assigns(:controller_node)).to eq("localhost")
    end

    context "when in EC2 framework" do
      before do
        create(:ec2_pillar)
        get :worker_bootstrap
      end

      it "assigns @instance_sizes" do
        expect(assigns(:instance_types)).to all(be_a(Velum::InstanceType))
      end

      it "renders EC2 view" do
        expect(response).to render_template(:worker_bootstrap_ec2)
      end
    end

    context "when in Azure framework" do
      before do
        create(:azure_pillar)
        get :worker_bootstrap
      end

      it "assigns @instance_sizes" do
        expect(assigns(:instance_types)).to all(be_a(Velum::InstanceType))
      end

      it "renders Azure view" do
        expect(response).to render_template(:worker_bootstrap_azure)
      end
    end
  end

  describe "POST /setup/worker-boostrap via HTML in EC2" do
    let(:instance_type) { "t2.xlarge" }
    let(:instance_count) { 5 }
    let(:subnet_id) { "subnet-9d4a7b6c" }
    let(:security_group_id) { "sg-903004f8" }
    let(:cloud_cluster_params) do
      {
        instance_type:     instance_type,
        instance_count:    instance_count,
        subnet_id:         subnet_id,
        security_group_id: security_group_id
      }
    end

    before do
      sign_in user
      create(:ec2_pillar)
      Pillar.create pillar: "dashboard", value: "localhost"

      allow(Velum::Salt).to receive(:build_cloud_cluster)
    end

    context "when saving succeeds" do
      before do
        ensure_pillar_refresh do
          post :build_cloud_cluster, cloud_cluster: cloud_cluster_params
        end
      end

      it "always uses the framework pillar" do
        expect(assigns(:cloud_cluster).cloud_framework).to eq("ec2")
      end

      it "assigns the instance type" do
        expect(assigns(:cloud_cluster).instance_type).to eq(instance_type)
      end

      it "assigns the quantity of workers" do
        expect(assigns(:cloud_cluster).instance_count).to eq(instance_count)
      end

      it "assigns the EC2 subnet ID" do
        expect(assigns(:cloud_cluster).subnet_id).to eq(subnet_id)
      end

      it "assigns the EC2 security group ID" do
        expect(assigns(:cloud_cluster).security_group_id).to eq(security_group_id)
      end

      it "calls salt-cloud" do
        expect(Velum::Salt).to have_received(:build_cloud_cluster).with(instance_count).once
      end

      it "uses a flash to provide confirmation" do
        expect(flash[:notice]).to be_present
      end
    end

    context "when saving fails" do
      let(:error_message) { "Nope!" }
      let(:mock_cloud_cluster) do
        mock = CloudCluster.new(cloud_cluster_params)
        allow(mock).to receive(:save!).and_raise(
          ActiveRecord::ActiveRecordError.new(error_message)
        )
        mock
      end

      before do
        allow(CloudCluster).to receive(:new).and_return(mock_cloud_cluster)
        post :build_cloud_cluster, cloud_cluster: cloud_cluster_params
      end

      it "redirects back to bootstrap" do
        expect(controller).to redirect_to(:setup_worker_bootstrap)
      end

      it "uses a flash to show error messages" do
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "POST /setup/worker-boostrap via HTML in Azure" do
    let(:instance_type) { "Standard_DS3_v2" }
    let(:instance_count) { 5 }
    let(:subscription_id) { SecureRandom.uuid }
    let(:tenant_id) { SecureRandom.uuid }
    let(:client_id) { SecureRandom.uuid }
    let(:secret) { SecureRandom.hex(16) }
    let(:resource_group) { "azureresourcegroup" }
    let(:storage_account) { "azurestorageaccount" }
    let(:subnet_id) { "azuresubnetname" }
    let(:network_id) { "azurenetworkname" }
    let(:cloud_cluster_params) do
      {
        subscription_id: subscription_id,
        tenant_id:       tenant_id,
        client_id:       client_id,
        secret:          secret,
        instance_type:   instance_type,
        instance_count:  instance_count,
        resource_group:  resource_group,
        network_id:      network_id,
        subnet_id:       subnet_id,
        storage_account: storage_account
      }
    end

    before do
      sign_in user
      create(:azure_pillar)
      Pillar.create pillar: "dashboard", value: "localhost"

      allow(Velum::Salt).to receive(:build_cloud_cluster)
    end

    context "when saving succeeds" do
      before do
        ensure_pillar_refresh do
          post :build_cloud_cluster, cloud_cluster: cloud_cluster_params
        end
      end

      it "always uses the framework pillar" do
        expect(assigns(:cloud_cluster).cloud_framework).to eq("azure")
      end

      it "assigns the subscription id" do
        expect(assigns(:cloud_cluster).subscription_id).to eq(subscription_id)
      end

      it "assigns the tenant id" do
        expect(assigns(:cloud_cluster).tenant_id).to eq(tenant_id)
      end

      it "assigns the service principal credentials" do
        expect(assigns(:cloud_cluster).client_id).to eq(client_id)
        expect(assigns(:cloud_cluster).secret).to eq(secret)
      end

      it "assigns the instance type" do
        expect(assigns(:cloud_cluster).instance_type).to eq(instance_type)
      end

      it "assigns the quantity of workers" do
        expect(assigns(:cloud_cluster).instance_count).to eq(instance_count)
      end

      it "assigns the Azure resource group" do
        expect(assigns(:cloud_cluster).resource_group).to eq(resource_group)
      end

      it "assigns the Azure storage account" do
        expect(assigns(:cloud_cluster).storage_account).to eq(storage_account)
      end

      it "assigns the Azure network id" do
        expect(assigns(:cloud_cluster).network_id).to eq(network_id)
      end

      it "assigns the Azure subnet id" do
        expect(assigns(:cloud_cluster).subnet_id).to eq(subnet_id)
      end

      it "calls salt-cloud" do
        expect(Velum::Salt).to have_received(:build_cloud_cluster).with(instance_count).once
      end

      it "uses a flash to provide confirmation" do
        expect(flash[:notice]).to be_present
      end
    end
  end

  describe "POST /setup/discovery via HTML" do
    let(:salt) { Velum::Salt }
    before do
      setup_done apiserver: false
      sign_in user
      Minion.create! [{ minion_id: SecureRandom.hex, fqdn: "master" },
                      { minion_id: SecureRandom.hex, fqdn: "worker0" }]
    end

    context "when the user successfully chooses the master" do
      it "sets the master" do
        post :set_roles, roles: { master: [Minion.first.id], worker: Minion.all[1..-1].map(&:id) }
        expect(Minion.first.role).to eq "master"
      end

      it "sets the other roles to minions" do
        post :set_roles, roles: { master: [Minion.first.id], worker: Minion.all[1..-1].map(&:id) }
        expect(Minion.where("fqdn REGEXP ?", "worker*").map(&:role).uniq).to eq ["worker"]
      end

      it "gets redirected to the bootstrap page" do
        post :set_roles, roles: { master: [Minion.first.id], worker: Minion.all[1..-1].map(&:id) }
        expect(response.redirect_url).to eq setup_bootstrap_url
        expect(response.status).to eq 302
      end
    end

    context "when the user fails to choose the master" do
      before do
        allow_any_instance_of(Minion).to receive(:assign_role).with(:master, remote: false)
          .and_return(false)
        allow_any_instance_of(Minion).to receive(:assign_role).with(:worker, remote: false)
          .and_return(true)
      end

      it "gets redirected to the discovery page" do
        post :set_roles, roles: { master: [Minion.first.id], worker: Minion.all[1..-1].map(&:id) }
        expect(flash[:error]).to be_present
        expect(response.redirect_url).to eq setup_discovery_url
      end
    end

    context "when the user bootstraps without selecting a master" do
      before do
        sign_in user
        Pillar.create pillar: "dashboard", value: "localhost"
      end

      it "warns and redirects to the setup" do
        post :set_roles, roles: {}
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq setup_discovery_url
      end
    end
  end

  describe "PUT /setup via HTML" do
    context "when the user configures the cluster successfully" do
      before do
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(true)
      end

      it "gets redirected to the setup_worker_bootstrap_path" do
        put :configure, settings: settings_params
        expect(response.redirect_url).to eq setup_worker_bootstrap_url
        expect(response.status).to eq 302
      end
    end

    context "when the user fails to configure the cluster" do
      before do
        setup_done apiserver: false
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(false)
      end

      it "gets redirected to the setup_worker_bootstrap_path with an error" do
        put :configure, settings: settings_params
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq setup_url
      end
    end

    context "proxy disabled" do
      let(:no_proxy_settings) do
        s = settings_params.dup
        s["dashboard"]    = "dashboard"
        s["apiserver"]    = "api.k8s.corporate.net"
        s["enable_proxy"] = "disable"
        s
      end

      let(:proxy_disabled_plus_leftovers) do
        s = no_proxy_settings.dup
        s["http_proxy"] = "squid.corp.net:3128"
        s["https_proxy"] = "squid.corp.net:3128"
        s["no_proxy"] = "localhost"
        s["proxy_systemwide"] = "true"
        s["enable_proxy"] = "disable"
        s
      end

      before do
        sign_in user
      end

      it "disable proxy systemwide" do
        put :configure, settings: no_proxy_settings

        expect(Pillar.value(pillar: :proxy_systemwide)).to eq("false")
      end

      it "erases proxy fields left by the user" do
        # A user could enable proxy, add some data and then disable it
        # before hitting the "submit" button.
        # In this case the proxy settings are still sent to Rails, but
        # the "disable the proxy" setting must have precedence.
        put :configure, settings: proxy_disabled_plus_leftovers

        [:http_proxy, :https_proxy, :no_proxy].each do |key|
          expect(Pillar.find_by(pillar: Pillar.all_pillars[key])).to be_nil
        end

        # this must be set to false, even though the value specied by the user
        # was different
        expect(Pillar.value(pillar: :proxy_systemwide)).to eq("false")
      end
    end

    context "when the user doesn't specify any values" do
      before do
        sign_in user
      end

      it "warns and redirects to the setup_path" do
        put :configure, settings: Hash[settings_params.map { |k, _| [k, ""] }]
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq setup_url
      end
    end

    context "when suse registry mirror is disabled" do
      let(:no_registry_mirror_settings) do
        settings_params.dup.tap do |s|
          s["dashboard"]                    = "dashboard"
          s["suse_registry_mirror_enabled"] = "disable"
        end
      end

      let(:registry_mirror_disabled_plus_leftovers) do
        no_registry_mirror_settings.dup.tap do |s|
          s["suse_registry_mirror_url"]  = "https://local.registry"
          s["suse_registry_mirror_cert"] = "something"
        end
      end

      before do
        sign_in user
      end

      it "doesn't store any related data" do
        put :configure, settings: no_registry_mirror_settings

        expect(Pillar.value(pillar: :suse_registry_mirror_url)).to be_nil
        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to be_nil
      end

      it "erases fields left by the user" do
        # A user could enable, add certificate and then disable certificate it
        # before hitting the "submit" button.
        # In this case the settings are still sent to Rails, but
        # the "disable the suse registry mirror certificate" setting must have precedence.
        put :configure, settings: registry_mirror_disabled_plus_leftovers

        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to be_nil
      end
    end

    context "when suse registry mirror weren't previously configured" do
      let(:registry_mirror_enabled) do
        settings_params.dup.tap do |s|
          s["dashboard"]                         = "dashboard"
          s["suse_registry_mirror_enabled"]      = "enable"
          s["suse_registry_mirror_cert_enabled"] = "enable"
          s["suse_registry_mirror_url"]          = "https://local.registry"
        end
      end

      let(:registry_mirror_enabled_plus_certificate) do
        registry_mirror_enabled.dup.tap do |s|
          s["suse_registry_mirror_cert"] = "something"
        end
      end

      before do
        sign_in user
      end

      it "stores registry without certificate" do
        put :configure, settings: registry_mirror_enabled

        expect(Pillar.value(pillar: :suse_registry_mirror_url)).to eq("https://local.registry")
        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to be_nil
      end

      it "stores registry and associate with the certificate" do
        put :configure, settings: registry_mirror_enabled_plus_certificate

        expect(Pillar.value(pillar: :suse_registry_mirror_url)).to eq("https://local.registry")
        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to eq("something")
      end
    end

    context "when suse registry mirror was previously configured" do
      let(:pillars) do
        {
          dashboard:                 "dashboard.example.com",
          suse_registry_mirror_url:  "https://local.registry",
          suse_registry_mirror_cert: "something"
        }
      end

      let(:registry_mirror_enabled_plus_certificate_leftover) do
        settings_params.dup.tap do |s|
          s["suse_registry_mirror_enabled"]      = "enable"
          s["suse_registry_mirror_cert_enabled"] = "disable"
          s["suse_registry_mirror_url"]          = "https://local.registry"
          s["suse_registry_mirror_cert"]         = "something"
        end
      end

      let(:registry_mirror_changed_plus_certificate) do
        settings_params.dup.tap do |s|
          s["suse_registry_mirror_enabled"]      = "enable"
          s["suse_registry_mirror_cert_enabled"] = "enable"
          s["suse_registry_mirror_url"]          = "https://local2.registry"
          s["suse_registry_mirror_cert"]         = "something"
        end
      end

      before do
        Pillar.apply(pillars, required_pillars: [:dashboard])

        sign_in user

        get :welcome
      end

      it "assigns @registry_mirror_url" do
        expect(assigns(:registry_mirror_url)).to eq("https://local.registry")
      end

      it "assigns @registry_mirror_cert" do
        expect(assigns(:registry_mirror_cert)).to eq("something")
      end

      it "assigns @registry_mirror_certificate_enabled" do
        expect(assigns(:registry_mirror_cert_enabled)).to eq(true)
      end

      it "assigns @registry_mirror_enabled" do
        expect(assigns(:registry_mirror_enabled)).to eq(true)
      end

      it "changes mirror url but keep the certificate" do
        put :configure, settings: registry_mirror_changed_plus_certificate

        expect(Pillar.value(pillar: :suse_registry_mirror_url)).to eq("https://local2.registry")
        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to eq("something")
      end

      it "erases certificate field left by the user if field disabled" do
        # A user could enable, add url and certificate and then disable it
        # before hitting the "submit" button.
        # In this case the settings are still sent to Rails, but
        # the "disable the suse registry mirror" setting must have precedence.
        put :configure, settings: registry_mirror_enabled_plus_certificate_leftover

        expect(Pillar.value(pillar: :suse_registry_mirror_url)).to eq("https://local.registry")

        # this must be set to nil, even though the value specied by the user
        # was different
        expect(Pillar.value(pillar: :suse_registry_mirror_cert)).to be_nil
      end
    end
  end

  describe "GET /setup/discovery" do
    before do
      sign_in user
      allow_any_instance_of(SetupController).to receive(:redirect_to_dashboard)
        .and_return(true)
      setup_stubbed_update_status!
    end

    it "shows the minions" do
      get :discovery
      expect(response.status).to eq 200
    end
  end

  describe "POST /setup/bootstrap" do
    before do
      sign_in user
      allow(Velum::Salt).to receive(:orchestrate)
      Minion.create! [{ minion_id: SecureRandom.hex, fqdn: "master", role: Minion.roles[:master] },
                      { minion_id: SecureRandom.hex, fqdn: "worker0", role: Minion.roles[:worker] }]
    end

    let(:settings_params) do
      {
        apiserver: "apiserver.example.com"
      }
    end

    context "when the pillar fails to save" do
      before do
        allow(Pillar).to receive(:apply).and_return(["apiserver could not be saved"])
      end

      it "redirects to bootstrap path and contains an alert" do
        post :do_bootstrap, settings: settings_params
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq setup_bootstrap_url
      end

      it "does not call the orchestration" do
        post :do_bootstrap, settings: settings_params
        expect(Velum::Salt).to have_received(:orchestrate).exactly(0).times
      end
    end

    context "when assigning roles fails on the remote end" do
      before do
        allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).and_return(false)
      end

      it "redirects to bootstrap path and contains an error" do
        post :do_bootstrap, settings: settings_params
        expect(flash[:error]).to be_present
        expect(response.redirect_url).to eq setup_bootstrap_url
      end

      it "does not call the orchestration" do
        post :do_bootstrap, settings: settings_params
        expect(Velum::Salt).to have_received(:orchestrate).exactly(0).times
      end
    end

    context "when assigning roles works on the remote end" do
      before do
        allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).and_return(true)
      end

      it "calls to the orchestration and redirects to the root path" do
        post :do_bootstrap, settings: settings_params
        expect(Velum::Salt).to have_received(:orchestrate).exactly(1).times
        expect(response.redirect_url).to eq root_url
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
