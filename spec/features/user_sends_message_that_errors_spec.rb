require 'rails_helper'

feature 'receiving messages', active_job: true do
  let(:message_body) { 'You have an appointment tomorrow at 10am' }
  let(:client_1) { create :client, users: [myuser] }
  let(:myuser) { create :user }
  let(:rr) { myuser.reporting_relationships.find_by(client: client_1) }

  before do
    login_as(myuser, scope: :user)
  end

  scenario 'client has blacklisted messages from clientcomm', :js, active_job: true do
    step 'when the client has texted stop' do
      visit reporting_relationship_path(rr)

      error = twilio_rest_error(21610, 'Blacklisted')
      expect_any_instance_of(FakeTwilioClient).to receive(:create).and_raise(error)

      fill_in 'Send a text message', with: message_body

      perform_enqueued_jobs do
        click_on 'send_message'

        wait_for("enqued jobs to finish") { page.all('.message--content').any? }
        expect(page).to have_ignoring_newlines message_body
        expect(page).to have_css '.blacklisted', text: I18n.t('message.status.blacklisted')
      end
    end
  end
end
