require 'spec_helper'

module Bosh::Director
  describe InstanceUpdater do
    let(:ip_repo) { DeploymentPlan::InMemoryIpRepo.new(logger) }
    let(:ip_provider) { DeploymentPlan::IpProvider.new(ip_repo, [], logger) }
    let(:updater) { InstanceUpdater.new_instance_updater(ip_provider) }
    let(:agent_client) { instance_double(AgentClient) }
    let(:instance_model) { Models::Instance.make(uuid: 'uuid-1', deployment: deployment_model, state: 'started', job: 'job-1', credentials: {'user' => 'secret'}, agent_id: 'scool', spec: {'stemcell' => {'name' => 'ubunut_1', 'version' => '8'}}) }
    let(:deployment_model) { Models::Deployment.make(name: 'deployment') }
    let(:instance) do
      az = DeploymentPlan::AvailabilityZone.new('az-1', {})
      vm_type = DeploymentPlan::VmType.new({'name' => 'small_vm'})
      stemcell = DeploymentPlan::Stemcell.new('ubuntu_stemcell', 'ubuntu_1', 'ubuntu', '8')
      instance = DeploymentPlan::Instance.new('job-1', 0, 'stopped', vm_type, [], stemcell, {}, false, deployment_model, {}, az, logger)
      instance.bind_existing_instance_model(instance_model)

      instance
    end
    let(:instance_plan) do
      job = instance_double(DeploymentPlan::Job, default_network: {})
      desired_instance = DeploymentPlan::DesiredInstance.new(job)
      instance_plan = DeploymentPlan::InstancePlan.new(existing_instance: instance_model, instance: instance, desired_instance: desired_instance)
      allow(instance_plan).to receive(:spec).and_return(DeploymentPlan::InstanceSpec.create_empty)

      instance_plan
    end

    before do
      allow(Config).to receive(:cloud).and_return(instance_double(Bosh::Cloud))
      allow(Config).to receive_message_chain(:current_job, :username).and_return('user')
      allow(Config).to receive_message_chain(:current_job, :task_id).and_return('task-1', 'task-2')
      allow(Config).to receive_message_chain(:current_job, :event_manager).and_return(Api::EventManager.new({}))
      allow(Bosh::Director::App).to receive_message_chain(:instance, :blobstores, :blobstore).and_return(instance_double(Bosh::Blobstore::Client))
    end

    context 'when stopping instances' do
      before do
        allow(AgentClient).to receive(:with_vm_credentials_and_agent_id).with({'user' => 'secret'}, 'scool').and_return(agent_client)
        allow(instance_plan).to receive(:changes).and_return([:state])
      end

      it 'should exit early without updating spec of instance' do
        expect(instance_model.state).to eq('started')
        expect(Models::Event.count).to eq 0

        expect(agent_client).to receive(:stop)
        expect(agent_client).to receive(:drain).and_return(0.1)
        expect(agent_client).not_to receive(:apply)

        updater.update(instance_plan)

        expect(instance_model.state).to eq('stopped')
        expect(instance_model.update_completed).to eq true
        expect(Models::Event.count).to eq 2
      end
    end

    context 'when changing DNS' do
      before do
        allow(instance_plan).to receive(:changes).and_return([:dns])
      end

      it 'should exit early without interacting at all with the agent' do
        instance_model.update(dns_record_names: ['old.dns.record'])
        expect(instance_model.state).to eq('started')
        expect(Models::Event.count).to eq 0

        expect(AgentClient).not_to receive(:with_vm_credentials_and_agent_id)

        subnet_spec = {
          'range' => '10.10.10.0/24',
          'gateway' => '10.10.10.1',
        }
        subnet = DeploymentPlan::ManualNetworkSubnet.parse('my-network', subnet_spec, ['az-1'], [])
        network = DeploymentPlan::ManualNetwork.new('my-network', [subnet], logger)
        reservation = ExistingNetworkReservation.new(instance_model, network, '10.10.10.10', :dynamic)
        instance_plan.network_plans = [DeploymentPlan::NetworkPlanner::Plan.new(reservation: reservation, existing: true)]
        updater.update(instance_plan)

        expect(instance_model.dns_record_names).to eq ['old.dns.record', '0.job-1.my-network.deployment.bosh', 'uuid-1.job-1.my-network.deployment.bosh']
        expect(instance_model.update_completed).to eq true
        expect(Models::Event.count).to eq 2
      end
    end

    context 'when something goes wrong in the update procedure' do
      before do
        allow(AgentClient).to receive(:with_vm_credentials_and_agent_id).with({'user' => 'secret'}, 'scool').and_return(agent_client)
        allow(instance_plan).to receive(:changes).and_return([:state])
      end

      it 'should always add an event recording the error' do
        expect(Models::Event.count).to eq 0

        drain_error = RpcRemoteException.new('Oh noes!')
        expect(agent_client).to receive(:drain).and_raise(drain_error)

        expect { updater.update(instance_plan) }.to raise_error drain_error
        expect(Models::Event.map(&:error)).to eq([nil, 'Oh noes!'])
      end
    end
  end
end
