require 'rails_helper'

RSpec.describe ReportingRelationship, type: :model do
  it { should belong_to :user }
  it { should belong_to :client }
  it { should belong_to :client_status }
  it { should have_one(:department).through(:user) }

  describe 'Validations' do
    it { should validate_presence_of :user }
    it { should validate_presence_of :client }
    it { should_not allow_value(nil).for :active }

    describe 'Client' do
      context 'An identical relationship' do
        let(:user) { create :user }
        let(:client) { create :client, user: user }

        it 'is invalid' do
          rr = ReportingRelationship.new(
            user: user,
            client: client
          )

          expect(rr).to_not be_valid
          expect(rr.errors.added?(:client, 'has already been taken')).to eq true
        end
      end

      context 'A relationship within the same department' do
        it 'is invalid' do
          department = create :department
          user1 = create :user, department: department
          user2 = create :user, department: department
          client = create :client, user: user1

          rr = ReportingRelationship.new(
            user: user2,
            client: client
          )

          expect(rr).to_not be_valid
          expect(rr.errors.added?(:client, :existing_dept_relationship, user_full_name: user1.full_name))
            .to eq true
        end

        context 'the reporting relationships itself is inactive' do
          it 'is valid' do
            department = create :department
            user1 = create :user, department: department
            user2 = create :user, department: department
            client = create :client, user: user1

            rr = ReportingRelationship.new(
              user: user2,
              client: client,
              active: false
            )

            expect(rr).to be_valid
          end
        end
      end
    end

    describe 'Category' do
      it { should validate_inclusion_of(:category).in_array(ReportingRelationship::CATEGORIES.keys) }
    end
  end

  describe '#deactivate' do
    let(:rr) { create :reporting_relationship, active: true }
    subject do
      rr.deactivate
    end
    it 'deactivates rr' do
      subject
      expect(rr).to_not be_active
    end
    context 'has scheduled messages' do
      before do
        create_list :text_message, 5, reporting_relationship: rr, send_at: Time.zone.now + 1.day
      end
      it 'marks messages as read' do
        subject
        expect(rr.reload.has_unread_messages).to eq(false)
        expect(rr.messages.unread).to be_empty
      end
      it 'deletes scheduled messages' do
        subject
        expect(rr.messages.scheduled).to be_empty
      end
    end
  end

  describe '#mark_messages_read' do
    let(:rr) { create :reporting_relationship, active: true, has_unread_messages: true }

    before do
      create_list :text_message, 5, read: false, inbound: true, twilio_status: 'received'
      rr.user.update!(has_unread_messages: true)
    end

    context 'do not update user' do
      subject { rr.mark_messages_read }

      it 'marks messages and rr read, but not user' do
        subject

        expect(rr.messages.unread.count).to eq 0
        expect(rr.reload.has_unread_messages).to be false
        expect(rr.user.reload.has_unread_messages).to be true
      end
    end

    context 'update user' do
      subject { rr.mark_messages_read(update_user: true) }

      it 'marks messages, rr, and user read' do
        subject

        expect(rr.messages.unread.count).to eq 0
        expect(rr.reload.has_unread_messages).to be false
        expect(rr.user.reload.has_unread_messages).to be false
      end
    end
  end

  describe '#merge_with' do
    let(:department) { create :department }
    let!(:user) { create :user, department: department }
    let(:other_user) { user }
    let(:phone_number) { '+14155555550' }
    let(:phone_number_display) { '(415) 555-5550' }
    let(:phone_number_selected) { '+14155555552' }
    let(:phone_number_selected_display) { '(415) 555-5552' }
    let(:first_name) { 'Feaven X.' }
    let(:first_name_selected) { 'Feaven' }
    let(:last_name) { 'Girma' }
    let(:last_name_selected) { 'Girma' }
    let(:client) { create :client, user: user, phone_number: phone_number, first_name: first_name, last_name: last_name }
    let(:client_selected) { create :client, user: user, phone_number: phone_number_selected, first_name: first_name_selected, last_name: last_name_selected }
    let(:full_name_client) { client }
    let(:phone_number_client) { client_selected }
    let(:rr) { ReportingRelationship.find_by(user: user, client: client) }
    let(:rr_selected) { ReportingRelationship.find_by(user: other_user, client: client_selected) }
    let(:copy_name) { false }

    subject do
      rr_selected.merge_with(rr, copy_name)
    end

    before do
      travel_to(4.days.ago) { create_list :text_message, 2, reporting_relationship: rr, read: true }
      travel_to(3.days.ago) { create_list :text_message, 3, reporting_relationship: rr, read: true }
      rr.update!(last_contacted_at: rr.messages.order(:send_at).last.send_at)
      travel_to(2.days.ago) { create_list :text_message, 3, reporting_relationship: rr_selected, read: true }
      travel_to(1.day.ago) { create_list :text_message, 2, reporting_relationship: rr_selected, read: true }
      rr_selected.update!(last_contacted_at: rr_selected.messages.order(:send_at).last.send_at)
    end

    it 'merges the clients' do
      subject

      rr_from = rr
      rr_to = rr_selected

      expect(rr_from.reload.active).to eq false
      expect(rr_from.messages.count).to eq 0
      expect(rr_to.reload.active).to eq true
      expect(rr_to.messages.where(type: TextMessage.to_s).count).to eq 10

      conversation_ends_marker = rr_to.messages.where(type: ConversationEndsMarker.to_s).first
      expect(conversation_ends_marker).to_not be_nil
      conversation_ends_marker_body = I18n.t(
        'messages.conversation_ends',
        full_name: "#{first_name} #{last_name}",
        phone_number: phone_number_display
      )
      expect(conversation_ends_marker.body).to eq(conversation_ends_marker_body)

      merged_with_marker = rr_to.messages.where(type: MergedWithMarker.to_s).first
      expect(merged_with_marker).to_not be_nil
      merged_with_marker_body = I18n.t(
        'messages.merged_with',
        from_full_name: "#{first_name} #{last_name}",
        from_phone_number: phone_number_display,
        to_full_name: "#{first_name_selected} #{last_name_selected}",
        to_phone_number: phone_number_selected_display
      )
      expect(merged_with_marker.body).to eq(merged_with_marker_body)
    end

    context 'the from relationship was contacted more recently than the to relationship' do
      before do
        rr_selected.messages.destroy_all
        travel_to(6.days.ago) { create_list :text_message, 3, reporting_relationship: rr_selected, read: true }
        travel_to(5.days.ago) { create_list :text_message, 2, reporting_relationship: rr_selected, read: true }
        rr_selected.update!(last_contacted_at: rr_selected.messages.order(:send_at).last.send_at)
      end

      it 'updates last_contacted_at' do
        rr_from = rr
        rr_to = rr_selected

        expect(rr_to.reload.last_contacted_at).to be < rr_from.last_contacted_at

        subject

        expect(rr_to.reload.last_contacted_at).to eq(rr_from.last_contacted_at)
      end
    end

    context 'the to relationship has never been contacted, and the from relationship has been' do
      before do
        rr_selected.messages.destroy_all
        rr_selected.update!(last_contacted_at: nil)
      end

      it 'updates last_contacted_at' do
        subject

        rr_from = rr
        rr_to = rr_selected

        expect(rr_to.reload.last_contacted_at).to eq(rr_from.last_contacted_at)
      end
    end

    context 'the from relationship has never been contacted, and the to relationship has been' do
      before do
        rr.messages.destroy_all
        rr.update!(last_contacted_at: nil)
      end

      it 'leaves last_contacted_at alone' do
        rr_to = rr_selected
        last_contacted_at_before = rr_to.last_contacted_at

        subject

        expect(rr_to.reload.last_contacted_at).to eq last_contacted_at_before
      end
    end

    context 'a RecordInvalid exception is raised during the merge' do
      before do
        allow_any_instance_of(ReportingRelationship).to receive(:update!).with(active: false).and_raise ActiveRecord::RecordInvalid
      end

      it 'rolls back changes' do
        expect { subject }.to raise_error(ActiveRecord::RecordInvalid)

        rr_from = rr_selected
        rr_to = rr

        expect(rr_from.reload.active).to eq true
        expect(rr_from.reload.messages.count).to eq 5
        expect(rr_to.reload.active).to eq true
        expect(rr_to.reload.messages.count).to eq 5

        conversation_ends_marker = rr_to.messages.where(type: ConversationEndsMarker.to_s).first
        expect(conversation_ends_marker).to be_nil
        merged_with_marker = rr_to.messages.where(type: MergedWithMarker.to_s).first
        expect(merged_with_marker).to be_nil
      end
    end

    context 'there are like messages' do
      before do
        m = create :text_message, reporting_relationship: rr, inbound: true, read: true
        create :text_message, reporting_relationship: rr, inbound: false, read: true, like_message: m
        ms = create :text_message, reporting_relationship: rr_selected, inbound: true, read: true
        create :text_message, reporting_relationship: rr_selected, inbound: false, read: true, like_message: ms
      end

      it 'merges the clients without validation errors' do
        expect { subject }.to_not raise_error

        rr_from = rr
        rr_to = rr_selected

        expect(rr_from.reload.active).to eq false
        expect(rr_from.messages.count).to eq 0
        expect(rr_to.reload.active).to eq true
        expect(rr_to.messages.where(type: TextMessage.to_s).count).to eq 14
      end
    end

    context 'there are unread messages only on the from relationship' do
      before do
        travel_to(3.days.ago) { create_list :text_message, 2, reporting_relationship: rr, read: false }
        rr.update!(has_unread_messages: true)
      end

      it 'updates the unread value on the to relationship' do
        rr_to = rr_selected
        expect(rr_to.has_unread_messages).to eq false

        subject

        expect(rr_to.reload.has_unread_messages).to eq true
      end
    end

    context 'there are unread messages only on the to relationship' do
      before do
        travel_to(1.day.ago) { create_list :text_message, 2, reporting_relationship: rr_selected, read: false }
        rr_selected.update!(has_unread_messages: true)
      end

      it 'does not overwrite the unread value on the to relationship' do
        rr_to = rr_selected
        expect(rr_to.has_unread_messages).to eq true

        subject

        expect(rr_to.reload.has_unread_messages).to eq true
      end
    end

    context 'there are values for category, notes, and status on the from relationship' do
      let(:category_from) { 'cat1' }
      let(:notes_from) { 'a note on the from relationship' }
      let(:status_from) { create :client_status, name: 'from status', department: department }

      before do
        rr_selected.update!(notes: nil)
        rr.update!(category: category_from, notes: notes_from, client_status: status_from)
      end

      context 'there are only values on the from relationship' do
        it 'copies the values to the to relationship' do
          subject

          rr_to = rr_selected
          expect(rr_to.reload.category).to eq category_from
          expect(rr_to.reload.notes).to eq notes_from
          expect(rr_to.reload.client_status).to eq status_from
        end
      end

      context 'there are conflicting values on the to relationship' do
        let(:category_to) { 'cat2' }
        let(:notes_to) { 'a note on the to relationship' }
        let(:status_to) { create :client_status, name: 'to status', department: department }

        before do
          rr_selected.update!(category: category_to, notes: notes_to, client_status: status_to)
        end

        it 'preserves the values on the to relationship' do
          subject

          rr_to = rr_selected
          expect(rr_to.reload.category).to eq category_to
          expect(rr_to.reload.notes).to eq notes_to
          expect(rr_to.reload.client_status).to eq status_to
        end
      end
    end
  end

  describe '#transfer_to' do
    let(:dept) { create :department }
    let(:old_user) { create :user, department: dept }
    let(:new_user) { create :user, department: dept }
    let(:client) { create :client, user: old_user }
    let(:rr) { ReportingRelationship.find_by(user: old_user, client: client) }
    let!(:scheduled_messages) { create_list :text_message, 5, reporting_relationship: rr, send_at: Time.zone.now + 1.day }
    let(:old_reporting_relationship) { ReportingRelationship.find_by(user: old_user, client: client) }
    let(:new_reporting_relationship) { ReportingRelationship.find_or_initialize_by(user_id: new_user.id, client_id: client.id) }

    before do
      rr.update!(has_unread_messages: true)
    end

    subject do
      old_reporting_relationship.transfer_to(new_reporting_relationship)
    end

    it 'transfers client to user' do
      subject

      expect(old_reporting_relationship.reload).to_not be_active
      expect(new_reporting_relationship.reload).to be_active
      expect(old_user.reload.has_unread_messages).to eq(false)
    end

    it 'creates transfer markers' do
      expect(Message).to receive(:create_transfer_markers).with(sending_rr: old_reporting_relationship, receiving_rr: new_reporting_relationship)
      subject
    end

    it 'transfers scheduled messages' do
      subject
      expect(old_user.messages.scheduled.count).to eq(0)
      expect(new_user.messages.scheduled).to contain_exactly(*scheduled_messages)
    end

    context 'the sending user is the unclaimed user' do
      let!(:messages) { create_list :text_message, 5, reporting_relationship: rr }

      before do
        dept.update(unclaimed_user: old_user)
      end

      it 'transfers all messages' do
        subject
        expect(old_user.messages.messages.count).to eq(0)
        expect(new_user.messages.messages).to include(*messages)
      end
    end

    context 'has client statuses' do
      let!(:status) { create :client_status, department: dept }

      before do
        old_reporting_relationship.client_status = status
        old_reporting_relationship.save!
      end

      it 'transfers client statuses' do
        subject
        old_reporting_relationship.reload
        new_reporting_relationship.reload
        expect(old_reporting_relationship.client_status).to eq(status)
        expect(new_reporting_relationship.client_status).to eq(status)
      end
    end
  end
end
