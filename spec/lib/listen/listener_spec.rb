require 'spec_helper'

describe Listen::Listener do
  let(:listener) { Listen::Listener.new(options) }
  let(:options) { {} }
  let(:registry) { instance_double(Celluloid::Registry, :[]= => true) }

  let(:supervisor) do
    instance_double(Celluloid::SupervisionGroup, add: true, pool: true)
  end

  let(:record) { instance_double(Listen::Record, terminate: true, build: true) }
  let(:silencer) { instance_double(Listen::Silencer, terminate: true) }
  let(:adapter) { instance_double(Listen::Adapter::Base, local_fs?: true) }
  let(:proxy) { instance_double(Celluloid::ActorProxy, terminate: true) }
  let(:change_pool_async) { instance_double(Listen::Change) }
  before do
    allow(Celluloid::Registry).to receive(:new) { registry }
    allow(Celluloid::SupervisionGroup).to receive(:run!) { supervisor }
    allow(registry).to receive(:[]).with(:silencer) { silencer }
    allow(registry).to receive(:[]).with(:adapter) { adapter }
    allow(registry).to receive(:[]).with(:record) { record }
    allow(registry).to receive(:[]).with(:change_pool) { proxy }

  end

  describe 'initialize' do
    it 'sets paused to false' do
      expect(listener).not_to be_paused
    end

    it 'sets block' do
      block = proc {}
      listener = Listen::Listener.new('lib', &block)
      expect(listener.block).not_to be_nil
    end

    it 'sets directories with realpath' do
      listener = Listen::Listener.new('lib', 'spec')
      expected = %w(lib spec).map { |dir| Pathname.pwd.join(dir) }
      expect(listener.directories).to eq expected
    end
  end

  describe 'options' do
    it 'sets default options' do
      expect(listener.options).to eq(
                                       debug: false,
                                       latency: nil,
                                       wait_for_delay: 0.1,
                                       force_polling: false,
                                       polling_fallback_message: nil)
    end

    it 'sets new options on initialize' do
      listener = Listen::Listener.new('lib',
                                      latency: 1.234,
                                      wait_for_delay: 0.85)

      expect(listener.options).to eq(
                                       debug: false,
                                       latency: 1.234,
                                       wait_for_delay: 0.85,
                                       force_polling: false,
                                       polling_fallback_message: nil)
    end
  end

  describe '#start' do
    before do
      allow(listener).to receive(:_start_adapter)
      allow(silencer).to receive(:silenced?) { false }
    end

    it 'registers silencer' do
      expect(supervisor).to receive(:add).
        with(Listen::Silencer, as: :silencer, args: listener)

      listener.start
    end

    it 'supervises change_pool' do
      expect(supervisor).to receive(:pool).
        with(Listen::Change, as: :change_pool, args: listener)

      listener.start
    end

    it 'supervises adaper' do
      allow(Listen::Adapter).to receive(:select) { Listen::Adapter::Polling }
      expect(supervisor).to receive(:add).
        with(Listen::Adapter::Polling, as: :adapter, args: listener)

      listener.start
    end

    it 'supervises record' do
      expect(supervisor).to receive(:add).
        with(Listen::Record, as: :record, args: listener)

      listener.start
    end

    it 'builds record' do
      expect(record).to receive(:build)
      listener.start
    end

    it 'sets paused to false' do
      listener.start
      expect(listener.paused).to be_falsey
    end

    it 'starts adapter' do
      expect(listener).to receive(:_start_adapter)
      listener.start
    end

    it 'calls block on changes' do
      foo = instance_double(
        Pathname,
        to_s: 'foo',
        exist?: true,
        directory?: false)

      listener.changes = [{ modified: foo }]
      block_stub = double('block')
      listener.block = block_stub
      expect(block_stub).to receive(:call).with(['foo'], [], [])
      listener.start
      sleep 0.25
    end
  end

  describe '#stop' do
    it 'terminates supervisor' do
      listener.supervisor = supervisor
      expect(supervisor).to receive(:terminate)
      listener.stop
    end
  end

  describe '#pause' do
    it 'sets paused to true' do
      listener.pause
      expect(listener.paused).to be_truthy
    end
  end

  describe '#unpause' do
    it 'builds record' do
      expect(record).to receive(:build)
      listener.unpause
    end

    it 'sets paused to false' do
      allow(record).to receive(:build)
      listener.unpause
      expect(listener.paused).to be_falsey
    end
  end

  describe '#paused?' do
    it 'returns true when paused' do
      listener.paused = true
      expect(listener).to be_paused
    end
    it 'returns false when not paused (nil)' do
      listener.paused = nil
      expect(listener).not_to be_paused
    end
    it 'returns false when not paused (false)' do
      listener.paused = false
      expect(listener).not_to be_paused
    end
  end

  describe '#listen?' do
    it 'returns true when not paused (false)' do
      listener.paused = false
      listener.stopping = false
      expect(listener.listen?).to be_truthy
    end
    it 'returns false when not paused (nil)' do
      listener.paused = nil
      listener.stopping = false
      expect(listener.listen?).to be_falsey
    end
    it 'returns false when paused' do
      listener.paused = true
      listener.stopping = false
      expect(listener.listen?).to be_falsey
    end
    it 'returns false when stopped' do
      listener.paused = false
      listener.stopping = true
      expect(listener.listen?).to be_falsey
    end
  end

  describe '#ignore' do
    let(:new_silencer) { instance_double(Listen::Silencer) }
    before { allow(Celluloid::Actor).to receive(:[]=) }

    it 'resets silencer actor' do
      expect(Listen::Silencer).to receive(:new).with(listener) { new_silencer }
      expect(registry).to receive(:[]=).with(:silencer, new_silencer)
      listener.ignore(/foo/)
    end

    context 'with existing ignore options' do
      let(:options) { { ignore: /bar/ } }

      it 'adds up to existing ignore options' do
        expect(Listen::Silencer).to receive(:new).with(listener)
        listener.ignore(/foo/)
        expect(listener.options).to include(ignore: [/bar/, /foo/])
      end
    end

    context 'with existing ignore options (array)' do
      let(:options) { { ignore: [/bar/] } }

      it 'adds up to existing ignore options' do
        expect(Listen::Silencer).to receive(:new).with(listener)
        listener.ignore(/foo/)
        expect(listener.options).to include(ignore: [[/bar/], /foo/])
      end
    end
  end

  describe '#ignore!' do
    let(:new_silencer) { instance_double(Listen::Silencer) }
    before { allow(Celluloid::Actor).to receive(:[]=) }

    it 'resets silencer actor' do
      expect(Listen::Silencer).to receive(:new).with(listener) { new_silencer }
      expect(registry).to receive(:[]=).with(:silencer, new_silencer)
      listener.ignore!(/foo/)
      expect(listener.options).to include(ignore!: /foo/)
    end

    context 'with existing ignore! options' do
      let(:options) { { ignore!: /bar/ } }

      it 'overwrites existing ignore options' do
        expect(Listen::Silencer).to receive(:new).with(listener)
        listener.ignore!([/foo/])
        expect(listener.options).to include(ignore!: [/foo/])
      end
    end

    context 'with existing ignore options' do
      let(:options) { { ignore: /bar/ } }

      it 'deletes ignore options' do
        expect(Listen::Silencer).to receive(:new).with(listener)
        listener.ignore!([/foo/])
        expect(listener.options).to_not include(ignore: /bar/)
      end
    end
  end

  describe '#only' do
    let(:new_silencer) { instance_double(Listen::Silencer) }
    before { allow(Celluloid::Actor).to receive(:[]=) }

    it 'resets silencer actor' do
      expect(Listen::Silencer).to receive(:new).with(listener) { new_silencer }
      expect(registry).to receive(:[]=).with(:silencer, new_silencer)
      listener.only(/foo/)
    end

    context 'with existing only options' do
      let(:options) { { only: /bar/ } }

      it 'overwrites existing ignore options' do
        expect(Listen::Silencer).to receive(:new).with(listener)
        listener.only([/foo/])
        expect(listener.options).to include(only: [/foo/])
      end
    end
  end

  describe '_wait_for_changes' do
    it 'gets two changes and calls the block once' do
      allow(silencer).to receive(:silenced?) { false }

      fake_time = 0
      allow(listener).to receive(:sleep) do |sec|
        fake_time += sec
        listener.stopping = true if fake_time > 1
      end

      listener.block = proc do |modified, added, _|
        expect(modified).to eql(['foo.txt'])
        expect(added).to eql(['bar.txt'])
      end

      foo = instance_double(
        Pathname,
        to_s: 'foo.txt',
        exist?: true,
        directory?: false)

      bar = instance_double(
        Pathname,
        to_s: 'bar.txt',
        exist?: true,
        directory?: false)

      i = 0
      allow(listener).to receive(:_pop_changes) do
        i += 1
        case i
        when 1
          []
        when 2
          [{ modified: foo }]
        when 3
          [{ added: bar }]
        else
          []
        end
      end

      listener.send :_wait_for_changes
    end
  end

  describe '_smoosh_changes' do
    it 'recognizes rename from temp file' do
      path = instance_double(
        Pathname,
        to_s: 'foo',
        exist?: true,
        directory?: false)

      changes = [
        { modified: path },
        { removed: path },
        { added: path },
        { modified: path }
      ]
      allow(silencer).to receive(:silenced?) { false }
      smooshed = listener.send :_smoosh_changes, changes
      expect(smooshed).to eq(modified: ['foo'], added: [], removed: [])
    end

    it 'recognizes deleted temp file' do
      path = instance_double(
        Pathname,
        to_s: 'foo',
        exist?: false,
        directory?: false)

      changes = [
        { added: path },
        { modified: path },
        { removed: path },
        { modified: path }
      ]
      allow(silencer).to receive(:silenced?) { false }
      smooshed = listener.send :_smoosh_changes, changes
      expect(smooshed).to eq(modified: [], added: [], removed: [])
    end

    it 'recognizes double move as modification' do
      # e.g. "mv foo x && mv x foo" is like "touch foo"
      path = instance_double(
        Pathname,
        to_s: 'foo',
        exist?: true,
        directory?: false)

      changes = [
        { removed: path },
        { added: path }
      ]
      allow(silencer).to receive(:silenced?) { false }
      smooshed = listener.send :_smoosh_changes, changes
      expect(smooshed).to eq(modified: ['foo'], added: [], removed: [])
    end

    context 'with cookie' do

      it 'recognizes single moved_to as add' do
        foo = instance_double(
          Pathname,
          to_s: 'foo',
          exist?: true,
          directory?: false)

        changes = [{ moved_to: foo , cookie: 4321 }]
        expect(silencer).to receive(:silenced?).with(foo, 'File') { false }
        smooshed = listener.send :_smoosh_changes, changes
        expect(smooshed).to eq(modified: [], added: ['foo'], removed: [])
      end

      it 'recognizes related moved_to as add' do
        foo = instance_double(
          Pathname,
          to_s: 'foo',
          exist?: true,
          directory?: false)

        bar = instance_double(
          Pathname,
          to_s: 'bar',
          exist?: true,
          directory?: false)

        changes = [
          { moved_from: foo , cookie: 4321 },
          { moved_to: bar, cookie: 4321 }
        ]

        expect(silencer).to receive(:silenced?).
          twice.with(foo, 'File') { false }

        expect(silencer).to receive(:silenced?).with(bar, 'File') { false }
        smooshed = listener.send :_smoosh_changes, changes
        expect(smooshed).to eq(modified: [], added: ['bar'], removed: [])
      end

      # Scenario with workaround for editors using rename()
      it 'recognizes related moved_to with ignored moved_from as modify' do

        ignored = instance_double(
          Pathname,
          to_s: 'foo',
          exist?: true,
          directory?: false)

        foo = instance_double(
          Pathname,
          to_s: 'foo',
          exist?: true,
          directory?: false)

        changes = [
          { moved_from: ignored, cookie: 4321 },
          { moved_to: foo , cookie: 4321 }
        ]
        expect(silencer).to receive(:silenced?).with(ignored, 'File') { true }
        expect(silencer).to receive(:silenced?).with(foo, 'File') { false }
        smooshed = listener.send :_smoosh_changes, changes
        expect(smooshed).to eq(modified: ['foo'], added: [], removed: [])
      end
    end

    context 'with no cookie' do
      it 'recognizes properly ignores files' do
        ignored = instance_double(
          Pathname,
          to_s: 'foo',
          exist?: true,
          directory?: false)

        changes = [{ modified: ignored }]
        expect(silencer).to receive(:silenced?).with(ignored, 'File') { true }
        smooshed = listener.send :_smoosh_changes, changes
        expect(smooshed).to eq(modified: [], added: [], removed: [])
      end
    end
  end
end
