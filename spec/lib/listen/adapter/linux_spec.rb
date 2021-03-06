require 'spec_helper'

describe Listen::Adapter::Linux do
  if linux?
    let(:listener) { instance_double(Listen::Listener) }
    let(:adapter) { described_class.new(listener) }

    describe '.usable?' do
      it 'returns always true' do
        expect(described_class).to be_usable
      end
    end

    describe '#initialize' do
      before do
        allow(listener).to receive(:directories) { [] }
      end
      it 'requires rb-inotify gem' do
        adapter.send(:_configure)
        expect(defined?(INotify)).to be
      end
    end

    # workaround: Celluloid ignores SystemExit exception messages
    describe 'inotify limit message' do
      let!(:adapter) { described_class.new(listener) }

      before do
        require 'rb-inotify'
        allow(listener).to receive(:directories) { ['foo/dir'] }
        fake_worker = double(:fake_worker)
        allow(fake_worker).to receive(:watch).and_raise(Errno::ENOSPC)

        fake_notifier = double(:fake_notifier, new: fake_worker)
        stub_const('INotify::Notifier', fake_notifier)
      end

      it 'should be shown before calling abort' do
        expected_message = described_class.const_get('INOTIFY_LIMIT_MESSAGE')
        expect(STDERR).to receive(:puts).with(expected_message)

        # Expect RuntimeError here, for the sake of unit testing (actual
        # handling depends on Celluloid supervisor setup, which is beyond the
        # scope of adapter tests)
        expect { adapter.start }.to raise_error RuntimeError, expected_message
      end
    end

    describe '_callback' do
      before do
        allow(listener).to receive(:directories) { [] }
      end

      let(:expect_change) do
        lambda do |change|
          allow_any_instance_of(Listen::Adapter::Base).
            to receive(:_notify_change).
            with(
              Pathname.new('path/foo.txt'),
              type: 'File',
              change: change,
              cookie: 123)
        end
      end

      let(:event_callback) do
        lambda do |flags|
          callback = adapter.send(:_callback)
          callback.call double(
            :inotify_event,
            name: 'foo.txt',
            watcher: double(:watcher, path: 'path'),
            flags: flags,
            cookie: 123)
        end
      end

      # use case: close_write is the only way to detect changes
      # on ecryptfs
      it 'recognizes close_write as modify' do
        expect_change.call(:modified)
        event_callback.call([:close_write])
      end

      it 'recognizes moved_to as moved_to' do
        expect_change.call(:moved_to)
        event_callback.call([:moved_to])
      end

      it 'recognizes moved_from as moved_from' do
        expect_change.call(:moved_from)
        event_callback.call([:moved_from])
      end
    end

  end

  if darwin?
    it "isn't usable on Darwin" do
      expect(described_class).to_not be_usable
    end
  end

  if windows?
    it "isn't usable on Windows" do
      expect(described_class).to_not be_usable
    end
  end

  if bsd?
    it "isn't usable on BSD" do
      expect(described_class).to_not be_usable
    end
  end

  specify { expect(described_class).to be_local_fs }

end
