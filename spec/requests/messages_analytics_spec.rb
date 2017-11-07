require 'rails_helper'

describe 'Tracking of message analytics events', type: :request do
  context 'GET#index' do
    it 'tracks a visit to the message index' do
      user = create :user
      sign_in user
      client = create :client, user: user

      get client_messages_path client
      expect(response.code).to eq '200'

      expect_analytics_events({
                                'client_messages_view' => {
                                  'client_id' => client.id,
                                }
                              })
    end
  end
end
