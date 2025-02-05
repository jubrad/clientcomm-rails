require 'rails_helper'

feature 'logged-out user visits manage client page' do
  scenario 'and is redirected to the login form' do
    my_user = create :user
    clientone = create :client, user: my_user
    visit edit_client_path(clientone.id)
    expect(page).to have_text 'Log in'
    expect(page).to have_current_path(new_user_session_path)
  end
end

feature 'user edits client', :js do
  let(:my_user) { create :user, full_name: 'Joshua Terrones' }
  let(:other_user) { create :user, full_name: 'Debra Nelson' }
  let(:phone_number) { '2024042233' }
  let(:phone_number_display) { '(202) 404-2233' }
  let!(:clientone) { create :client, user: my_user, phone_number: phone_number }
  let(:new_first_name) { 'Vinicius' }
  let(:new_last_name) { 'Lima' }
  let(:new_note) { 'Here is a note.' }
  let(:new_phone_number) { '2024042234' }
  let(:new_phone_number_display) { '(202) 404-2234' }
  let(:future_date) { Time.zone.now.change(min: 0, day: 3) + 1.month }

  let(:unread_error_message) { 'You have unread messages from this client. The messages will not be transferred to the new user. Transfer now, or click here to read them.' }
  let(:unread_deactivate_error_message) { 'You have unread messages from this client. These messages will be marked as read. Deactivate, or click here to read them.' }

  before do
    FeatureFlag.create!(flag: 'court_dates', enabled: true)
    other_user.clients << clientone
    login_as my_user, scope: :user
    visit root_path
  end

  scenario 'successfully' do
    step 'navigates to edit client form' do
      within "tr#client_#{clientone.id}" do
        find('td.next-court-date-at', text: '--').click
      end

      expect(page).to have_current_path(edit_client_path(clientone))
      expect(page).to have_ignoring_newlines("also assigned to #{other_user.full_name}")
      expect(find_field('Phone number').value).to eq(phone_number_display)
    end

    step 'fills and submits edit client form' do
      fill_in 'First name', with: new_first_name
      fill_in 'Last name', with: new_last_name
      fill_in 'Notes', with: new_note
      fill_in 'Phone number', with: new_phone_number

      fill_in id: 'client_next_court_date_at', with: ' '
      find('.ui-datepicker-next').click
      click_on future_date.strftime('%-d')

      old_name = clientone.full_name
      click_on 'Save changes'

      emails = ActionMailer::Base.deliveries
      expect(emails.count).to eq 1
      expect(emails.first.html_part.to_s).to include "#{old_name}'s name is now"
    end

    step 'loads the conversation page' do
      clientone.reload
      rr = my_user.reporting_relationships.find_by(client: clientone)
      expect(page).to have_current_path(reporting_relationship_path(rr))
      expect(page).to have_ignoring_newlines "#{new_first_name} #{new_last_name}"
      expect(page).to have_content new_phone_number_display
      expect(page).to have_css '.message--event', text:
        I18n.t(
          'messages.phone_number_edited_by_you',
          new_phone_number: new_phone_number_display
        )
    end

    step 'navigates to edit client form and edits the client' do
      click_on 'Manage client'
      expect(find_field('Notes').value).to eq new_note
      expect(page).to have_field('First name', with: new_first_name)
      expect(page).to have_field('Last name', with: new_last_name)
      expect(page).to have_field('Phone number', with: new_phone_number_display)
      expect(page).to have_field('Court date (optional)', with: future_date.strftime('%m/%d/%Y'))
    end

    step 'visits client list and clicks on court date to edit client' do
      visit root_path
      click_on future_date.strftime('%m/%d/%Y')
      expect(page).to have_current_path(edit_client_path(clientone))
    end

    step 'logs in as the other user' do
      logout(my_user)
      page.reset!
      login_as other_user, scope: :user
      visit root_path
    end

    step 'loads the conversation page' do
      click_on clientone.full_name
      other_rr = other_user.reporting_relationships.find_by(client: clientone)
      expect(page).to have_current_path(reporting_relationship_path(other_rr))
      expect(page).to have_css '.message--event', text:
        I18n.t(
          'messages.phone_number_edited',
          user_full_name: my_user.full_name,
          new_phone_number: new_phone_number_display
        )
    end
  end

  context 'there are unread messages' do
    let(:rr) { ReportingRelationship.find_by(user: my_user, client: clientone) }

    before do
      create :text_message, reporting_relationship: rr, read: false, inbound: true
    end

    scenario 'it shows a warning about the unread messages' do
      within "tr#client_#{clientone.id}" do
        find('td.next-court-date-at', text: '--').click
      end

      expect(page).to have_current_path(edit_client_path(clientone))
      expect(page).to have_ignoring_newlines(unread_error_message)
      expect(page).to have_ignoring_newlines(unread_deactivate_error_message)
    end
  end

  context 'a message is received while editing' do
    let(:rr) { ReportingRelationship.find_by(user: my_user, client: clientone) }

    before do
      rr.update!(has_unread_messages: true)
    end

    scenario 'the page displays the warning when the message is received' do
      within "tr#client_#{clientone.id}" do
        find('td.next-court-date-at', text: '--').click
      end

      expect(page).to have_current_path(edit_client_path(clientone))
      expect(page).to_not have_ignoring_newlines(unread_error_message)
      expect(page).to_not have_ignoring_newlines(unread_deactivate_error_message)

      twilio_post_sms(twilio_new_message_params(
                        from_number: clientone.phone_number,
                        to_number: my_user.department.phone_number
      ))

      wait_for_ajax
      expect(page).to have_ignoring_newlines(unread_error_message)

      within '.unread-warning.deactivate' do
        find_link('click here', href: reporting_relationship_path(rr))
      end

      within '.unread-warning.transfer' do
        click_on 'click here'
      end

      expect(page).to have_current_path(reporting_relationship_path(rr))
    end
  end

  context 'the notes field is hidden by feature flag' do
    before do
      FeatureFlag.create!(flag: 'hide_notes', enabled: true)
    end

    scenario 'successfully submits form' do
      step 'navigates to edit client form' do
        within "tr#client_#{clientone.id}" do
          find('td.next-court-date-at', text: '--').click
        end

        expect(page).to have_current_path(edit_client_path(clientone))
        expect(page).to_not have_css 'input#client_reporting_relationships_attributes_0_notes'
      end

      step 'fills and submits edit client form' do
        fill_in 'First name', with: new_first_name
        fill_in 'Last name', with: new_last_name
        fill_in 'Phone number', with: new_phone_number

        click_on 'Save changes'

        rr = my_user.reporting_relationships.find_by(client: clientone)
        expect(page).to have_current_path(reporting_relationship_path(rr))
        expect(page).to_not have_ignoring_newlines rr.notes.truncate(40, separator: ' ', omission: '...')
      end
    end
  end

  scenario 'and fails validation' do
    step 'navigates to edit client form' do
      within "tr#client_#{clientone.id}" do
        find('td.next-court-date-at', text: '--').click
      end
      expect(page).to have_current_path(edit_client_path(clientone))
    end

    step 'submits empty last name' do
      fill_in 'Last name', with: ''
      click_on 'Save changes'
      
      expect(page).to have_content 'Edit client'
      expect(page).to have_css '.text--error', text: "can't be blank"
    end

    step 'cancels the edit' do
      click_on 'Cancel'
    end

    step 'navigates to edit client form' do
      within "tr#client_#{clientone.id}" do
        find('td.next-court-date-at', text: '--').click
      end
      expect(page).to have_current_path(edit_client_path(clientone))
    end

    step 'submits badly formatted next court date' do
      fill_in id: 'client_next_court_date_at', with: '111'
      find('input#client_next_court_date_at').send_keys(:escape)
      click_on 'Save changes'
      expect(page).to have_content 'Edit client'
      expect(page).to have_ignoring_newlines I18n.t('activerecord.errors.models.client.attributes.next_court_date_at.invalid')
    end
  end
end
