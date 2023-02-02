require 'rails_helper'

feature 'user transfers client', :js, active_job: true do
  let!(:myuser) { create :user }
  let!(:transfer_user) { create :user, department: myuser.department }
  let!(:unclaimed_user) { create :user, department: myuser.department }
  let!(:other_user) { create :user }
  let!(:clientone) { create :client, user: myuser, first_name: 'Client', last_name: 'One' }
  let!(:clienttwo) { create :client, user: myuser, first_name: 'Client', last_name: 'Two' }

  let(:note) { 'I am transfering this client to you' }

  before do
    myuser.department.update(user_id: unclaimed_user.id)
    other_user.clients << clientone
    login_as myuser, scope: :user
    visit root_path
  end

  scenario 'successfully' do
    step 'editing a client' do
      expect(page).to have_content clientone.full_name

      within "#client_#{clientone.id}" do
        find('td', text: 'Manage').click
      end
      expect(page).to have_current_path(edit_client_path(clientone))
      expect(page).to have_content("also assigned to #{other_user.full_name}")
      expect(page).to_not have_css 'select#reporting_relationship_user_id', text: myuser.full_name
      unclaimed_user = User.find(myuser.department.user_id)
      expect(page).to_not have_css 'select#reporting_relationship_user_id', text: unclaimed_user.full_name
    end

    step 'submitting transfer form without selecting a client' do
      perform_enqueued_jobs do
        click_on "Transfer #{clientone.full_name}"
      end
      expect(page).to have_content I18n.t('activerecord.errors.models.reporting_relationship.attributes.user.blank')
    end

    step 'transferring a client' do
      select transfer_user.full_name, from: 'reporting_relationship_user_id'
      fill_in 'transfer_note', with: note

      @time_send = Time.zone.now
      travel_to @time_send do
        perform_enqueued_jobs do
          click_on "Transfer #{clientone.full_name}"
        end
      end

      emails = ActionMailer::Base.deliveries

      expect(emails.count).to eq 1
      expect(emails.first.html_part.to_s).to include clientone.full_name
      expect(emails.first.html_part.to_s).to include clientone.phone_number
      expect(emails.first.html_part.to_s).to include note
    end

    step 'viewing clients list' do
      expect(page).to have_current_path(clients_path)
      expect(page).to have_css '.flash p', text: "#{clientone.full_name} was transferred to #{transfer_user.full_name}"

      expect(page).to_not have_css '#client-list', text: clientone.full_name
    end

    step 'transfer user has client' do
      logout(:user)

      login_as transfer_user, scope: :user
      visit root_path
      expect(page).to have_content clientone.full_name

      click_on clientone.full_name

      message_list = find('#message-list')
      expect(message_list).to have_ignoring_newlines I18n.t('messages.empty', client_first_name: clientone.first_name)
      expect(message_list.find(".message--event")).to have_ignoring_newlines "#{I18n.t('messages.transferred_from', client_full_name: clientone.full_name, user_full_name: myuser.full_name)} #{@time_send.strftime('%-m/%-d/%y, %-l:%M%P')}"
    end

    step 'transferring the client back' do
      click_on 'Manage client'

      select myuser.full_name, from: 'reporting_relationship_user_id'

      @time_return = Time.zone.now
      travel_to @time_return do
        perform_enqueued_jobs do
          click_on "Transfer #{clientone.full_name}"
        end
      end
      visit root_path
      expect(page).to_not have_content clientone.full_name
    end

    step 'original user has both transfer markers' do
      logout(:user)
      login_as myuser, scope: :user
      visit root_path
      expect(page).to have_content clientone.full_name

      click_on clientone.full_name

      expect(page).to have_ignoring_newlines I18n.t('messages.empty', client_first_name: clientone.first_name)
      expect(page).to have_ignoring_newlines "#{I18n.t('messages.transferred_to', user_full_name: transfer_user.full_name)} #{@time_send.strftime('%-m/%-d/%y, %-l:%M%P')}"
      expect(page).to have_ignoring_newlines "#{I18n.t('messages.transferred_from', client_full_name: clientone.full_name, user_full_name: transfer_user.full_name)} #{@time_return.strftime('%-m/%-d/%y, %-l:%M%P')}"
    end
  end
end
