# frozen_string_literal: true

require 'spec_helper'
require_relative '../../tasks/resolve_reference.rb'

describe Terraform do
  let(:terraform_dir) { File.expand_path(File.join(__dir__, '../fixtures/terraform_dir')) }
  let(:resource_type) { 'google_compute_instance.*' }
  let(:uri) { 'network_interface.0.access_config.0.nat_ip' }

  describe "#load_statefile" do
    it 'reads the terraform state file from the given directory' do
      statefile = File.join(terraform_dir, 'terraform.tfstate')
      state = subject.load_statefile(dir: terraform_dir)

      expect(state).to eq(JSON.parse(File.read(statefile)))
    end

    it 'accepts another name for the state file' do
      statefile = File.join(terraform_dir, 'empty.tfstate')
      state = subject.load_statefile(dir: terraform_dir, statefile: 'empty.tfstate')

      expect(state).to eq(JSON.parse(File.read(statefile)))
    end
  end

  shared_examples('loading terraform targets') do
    let(:opts) do
      { dir: terraform_dir,
        statefile: statefile,
        resource_type: resource_type,
        uri: uri }
    end

    it 'matches resources that start with the given type' do
      targets = subject.resolve_reference(opts)

      expect(targets).to contain_exactly({ 'uri' => ip0 }, 'uri' => ip1)
    end

    it 'can filter resources by regex' do
      targets = subject.resolve_reference(opts.merge(resource_type: 'google_compute_instance.example.\d+'))

      expect(targets).to contain_exactly({ 'uri' => ip0 }, 'uri' => ip1)
    end

    it 'maps inventory to name' do
      targets = subject.resolve_reference(opts.merge(name: 'id'))

      expect(targets).to contain_exactly({ 'uri' => ip0, 'name' => 'test-instance-0' },
                                         'uri' => ip1, 'name' => 'test-instance-1')
    end

    it 'sets only name if uri is not specified' do
      opts.delete(:uri)
      targets = subject.resolve_reference(opts.merge(name: 'id'))

      expect(targets).to contain_exactly({ 'name' => 'test-instance-0' },
                                         'name' => 'test-instance-1')
    end

    it 'builds a config map from the inventory' do
      config_template = { 'ssh' => { 'user' => 'metadata.sshUser' } }
      targets = subject.resolve_reference(opts.merge(config: config_template))

      config = { 'ssh' => { 'user' => 'someone' } }
      expect(targets).to contain_exactly({ 'uri' => ip0, 'config' => config },
                                         'uri' => ip1, 'config' => config)
    end

    it 'returns nothing if there are no matching resources' do
      targets = subject.resolve_reference(opts.merge(resource_type: 'aws_instance'))

      expect(targets).to be_empty
    end

    it 'fails if the state file does not exist' do
      expect { subject.resolve_reference(opts.merge(statefile: 'nonexistent.tfstate')) }
        .to raise_error(/Could not load Terraform state file nonexistent.tfstate/)
    end
  end

  describe "using a terrform version 3 state file" do
    let(:statefile) { 'terraform3.tfstate' }
    let(:ip0) { '34.83.150.52' }
    let(:ip1) { '34.83.16.240' }

    include_examples 'loading terraform targets'
  end

  describe "using a terraform version 4 state file" do
    let(:statefile) { 'terraform.tfstate' }
    let(:ip0) { '34.83.160.116' }
    let(:ip1) { '35.230.3.44' }

    include_examples 'loading terraform targets'
  end

  describe "#task" do
    it 'returns the list of targets' do
      opts = { dir: 'foo', resource_type: 'bar' }
      targets = [
        { "uri": "1.2.3.4", "name": "my-instance" },
        { "uri": "1.2.3.5", "name": "my-other-instance" }
      ]
      allow(subject).to receive(:resolve_reference).and_return(targets)

      result = subject.task(opts)
      expect(result).to have_key(:value)
      expect(result[:value]).to eq(targets)
    end

    it 'returns an error if one is raised' do
      error = TaskHelper::Error.new('something went wrong', 'bolt.test/error')
      allow(subject).to receive(:resolve_reference).and_raise(error)
      result = subject.task({})

      expect(result).to have_key(:_error)
      expect(result[:_error]['msg']).to match(/something went wrong/)
    end
  end
end
