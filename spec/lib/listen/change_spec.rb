require 'spec_helper'

describe Listen::Change do
  let(:subject) { Listen::Change.new(listener) }
  let(:listener) { instance_double(Listen::Listener, options: {}) }
  let(:record) { double(Listen::Record) }
  let(:file_path) { Pathname.new('file_path') }

  before do
    allow(listener).to receive(:sync).with(:record) { record }
    allow(listener).to receive(:async).with(:change_pool) { subject }
  end

  describe '#change' do
    let(:silencer) { instance_double(Listen::Silencer, silenced?: false) }
    before { allow(listener).to receive(:silencer) { silencer } }

    context 'file' do
      context 'with known change' do
        let(:file_path) { Pathname('file_path') }
        it 'notifies change directly to listener' do
          expect(listener).to receive(:queue).with(:modified, file_path, {})

          options = { type: 'File', change: :modified }
          subject.change(file_path, options)
        end

        it "doesn't notify to listener if path is silenced" do
          expect(silencer).to receive(:silenced?).and_return(true)
          expect(listener).to_not receive(:queue)

          options = { type: 'File', change: :modified }
          subject.change(file_path, options)
        end
      end

      context 'with unknown change' do

        it 'calls Listen::File#change' do
          expect(Listen::File).to receive(:change).with(record, file_path)

          subject.change(file_path, type: 'File')
        end

        it "doesn't call Listen::File#change if path is silenced" do
          expect(silencer).to receive(:silenced?).
            with(file_path, 'File').and_return(true)

          expect(Listen::File).to_not receive(:change)

          subject.change(file_path, type: 'File')
        end

        context 'that returns a change' do
          before { allow(Listen::File).to receive(:change) { :modified } }

          context 'listener listen' do
            before { allow(listener).to receive(:listen?) { true } }

            it 'notifies change to listener' do
              file_path = instance_double(Pathname,
                                          to_s: 'file_path',
                                          exist?: true)

              expect(listener).to receive(:queue).with(:modified, file_path)
              subject.change(file_path, type: 'File')
            end

            context 'silence option' do
              it 'notifies change to listener' do
                expect(listener).to_not receive(:queue)
                options = { type: 'File', silence: true }
                subject.change(file_path, options)
              end
            end
          end

          context "listener doesn't listen" do
            before { allow(listener).to receive(:listen?) { false } }

            it 'notifies change to listener' do
              expect(listener).to_not receive(:queue)
              subject.change(file_path, type: 'File')
            end
          end
        end

        context 'that returns no change' do
          before { allow(Listen::File).to receive(:change) { nil } }

          it "doesn't notifies no change" do
            expect(listener).to_not receive(:queue)
            subject.change(file_path, type: 'File')
          end
        end
      end
    end

    context 'directory' do
      let(:dir_options) { { type: 'Dir', recursive: true } }
      let(:dir_path) { Pathname.new('dir_path') }

      it 'calls Listen::Directory#new' do
        expect(Listen::Directory).to receive(:scan).
          with(subject, record, dir_path, dir_options)

        subject.change(dir_path, dir_options)
      end
    end
  end
end
