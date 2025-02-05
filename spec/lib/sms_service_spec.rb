require 'rails_helper'
require 'cgi'

describe SMSService do
  let(:twilio_client) { FakeTwilioClient.new sid, token }
  let(:message_sid) { Faker::Crypto.sha1 }
  let(:sid) { Rails.configuration.x.twilio.account_sid }
  let(:token) { Rails.configuration.x.twilio.auth_token }

  let(:sms_service) { described_class.clone.instance }

  before do
    @sid = ENV['TWILIO_ACCOUNT_SID']
    @token = ENV['TWILIO_AUTH_TOKEN']

    ENV['TWILIO_ACCOUNT_SID'] = sid
    ENV['TWILIO_AUTH_TOKEN'] = token

    allow(Twilio::REST::Client).to receive(:new).with(sid, token).and_return(twilio_client)
  end

  after do
    ENV['TWILIO_ACCOUNT_SID'] = @sid
    ENV['TWILIO_AUTH_TOKEN'] = @token
  end

  describe '#send_message' do
    let(:status_callback) { 'whocares.com' }
    let(:message) { create :text_message, twilio_sid: nil, twilio_status: nil, inbound: false }
    let(:message_status) { ['accepted', 'queued', 'sending', 'sent', 'receiving', 'received', 'delivered'].sample }
    let(:response) { double('response', sid: message_sid, status: message_status) }

    subject do
      sms_service.send_message(
        to: message.client.phone_number,
        from: message.number_from,
        body: message.body,
        status_callback: status_callback,
        media_url: nil
      )
    end

    before do
      allow(MessageBroadcastJob).to receive(:perform_now)
      allow(twilio_client).to receive(:create).and_return(response)
    end

    it 'returns the twilio sid and status' do
      expect(subject).to eq(MessageInfo.new(message_sid, message_status))
    end

    context 'there is a media url' do
      before do
        create :attachment, message: message
      end

      subject do
        sms_service.send_message(
          to: message.client.phone_number,
          from: message.number_from,
          body: message.body,
          media_url: message.reload.attachments.first.media.url,
          status_callback: status_callback
        )
      end

      it 'returns the twilio sid and status' do
        expect(twilio_client).to receive(:create).with(
          to: message.client.phone_number,
          from: message.number_from,
          body: message.body,
          media_url: message.reload.attachments.first.media.url,
          status_callback: status_callback
        )
        expect(subject).to eq(MessageInfo.new(message_sid, message_status))
      end
    end
  end

  describe '#status_lookup' do
    let(:message) { create :text_message, twilio_sid: message_sid }
    let(:twilio_message) { double('twilio_message', status: 'delivered') }

    subject { sms_service.status_lookup(message: message) }

    before do
      allow(twilio_client).to receive(:messages)
        .with(message_sid)
        .and_return(double('messages', fetch: twilio_message))
    end

    it 'returns the message status' do
      expect(subject).to eq 'delivered'
    end
  end

  describe '#message_lookup' do
    let(:twilio_message) { double('twilio_message') }

    subject { sms_service.message_lookup(twilio_sid: message_sid) }

    before do
      allow(twilio_client).to receive(:messages)
        .with(message_sid)
        .and_return(double('messages', fetch: twilio_message))
    end

    it 'returns the message object' do
      expect(subject).to eq twilio_message
    end
  end

  describe '#redact_message' do
    let(:message) { double('twilio_message', twilio_sid: message_sid, id: 22) }
    let(:media_one) { double('media') }
    let(:media_two) { double('media') }
    let(:media_list) { [media_one, media_two] }

    subject { sms_service.redact_message(message: message) }

    before do
      allow(Rails.logger).to receive :warn
      allow(twilio_client).to receive(:messages).with(message_sid).and_return(twilio_client)
      allow(twilio_client).to receive(:fetch).and_return(message)
      allow(message).to receive(:update)
      allow(message).to receive(:num_media).and_return('0')
      allow(media_one).to receive(:delete)
      allow(media_two).to receive(:delete)
    end

    it 'calls redact on the message' do
      expect(Rails.logger).to receive(:warn).with("redacting #{message.id}")
      expect(Rails.logger).to receive(:warn).with("deleting 0 media items from message #{message.id}")
      expect(message).to receive(:update).with(body: '')

      expect(subject).to eq true
    end

    context 'messages has attached media' do
      before do
        allow(message).to receive(:num_media).and_return('2')
      end

      it 'deletes any associated media' do
        expect(Rails.logger).to receive(:warn).with("deleting 2 media items from message #{message.id}")
        expect(message).to receive(:media).and_return(double('list', list: media_list))

        media_list.each do |media|
          expect(media).to receive(:delete)
        end

        expect(subject).to eq true
      end
    end

    context 'message fails to update' do
      let(:error_message) { 'Unable to update record: Cannot delete message because delivery has not been completed.' }

      it 'returns false' do
        expect(message).to receive(:update).with(body: '').and_raise(twilio_rest_error(20009, error_message))

        expect(subject).to eq false
      end
    end

    context 'twilio cannot find the message' do
      let(:error_message) { 'Unable to fetch record: The requested resource was not found' }

      before do
        expect_any_instance_of(FakeTwilioClient).to receive(:fetch).and_raise(twilio_rest_error(20404, error_message))
      end

      it 'returns false' do
        expect(subject).to eq false
      end
    end

    context 'an unknown twilio error occurs' do
      let(:error) { twilio_rest_error(20010, 'some other error')}

      it 'reraises the error' do
        expect(message).to receive(:update).with(body: '').and_raise(error)

        expect { subject }.to raise_error(error)
      end
    end
  end

  describe '#number_lookup' do
    let(:phone_numbers) { double('phone_numbers') }
    let(:phone_number) { '12345678910' }

    subject { sms_service.number_lookup(phone_number: phone_number) }

    it 'looks up the phone number' do
      expect(twilio_client).to receive(:phone_numbers).with(ERB::Util.url_encode(phone_number)).and_return(phone_numbers)
      expect(phone_numbers).to receive(:fetch)
        .with(no_args)
        .and_return(double('phone_number', phone_number: 'some phone number'))

      expect(subject).to eq('some phone number')
    end

    context 'the number does not exist' do
      let(:error) { twilio_rest_error(20404, 'Unable to fetch record') }
      it 'throws a number not found error' do
        expect(twilio_client).to receive(:phone_numbers).with(ERB::Util.url_encode(phone_number)).and_return(phone_numbers)
        expect(phone_numbers).to receive(:fetch).and_raise(error)

        expect { subject }.to raise_error(SMSService::NumberNotFound)
      end

      context 'an unknown twilio error occurs' do
        let(:error) {twilio_rest_error(20010, "some other error") }

        it 'reraises the error' do
          expect(twilio_client).to receive(:phone_numbers).with(ERB::Util.url_encode(phone_number)).and_return(phone_numbers)
          expect(phone_numbers).to receive(:fetch).and_raise(error)

          expect { subject }.to raise_error(error)
        end
      end
    end
  end

  describe '#twilio_params' do
    let(:number_from) { '+14155551111' }
    let(:number_to) { '+14155551112' }
    let(:twilio_sid) { Faker::Crypto.sha1 }
    let(:twilio_status) { 'delivered' }
    let(:body) { Faker::Lorem.sentence }
    let(:message) {
      double(
        'twilio_message',
        from: number_from,
        to: number_to,
        sid: twilio_sid,
        status: twilio_status,
        body: body,
        num_media: num_media,
        media: media
      )
    }

    subject { sms_service.twilio_params(twilio_message: message) }

    context 'message does not have media' do
      let(:num_media) { '0' }
      let(:media) { double('twilio_media', list: []) }

      it 'returns the reformatted parameters' do
        expect(subject).to include(
          From: number_from,
          To: number_to,
          SmsSid: twilio_sid,
          SmsStatus: twilio_status,
          Body: body,
          NumMedia: num_media
        )
      end
    end

    context 'message has media' do
      let(:api_root) { 'https://api.twilio.com' }
      let(:num_media) { '2' }
      let(:uri_one) { '/uri_one' }
      let(:uri_two) { '/uri_two' }
      let(:media_one) { double('twilio_media_object', uri: uri_one) }
      let(:media_two) { double('twilio_media_object', uri: uri_two) }
      let(:media) { double('twilio_media', list: [media_one, media_two]) }

      it 'returns properly formatted media parameters' do
        expect(subject).to include(
          NumMedia: num_media,
          MediaUrl0: "#{api_root}#{uri_one}",
          MediaUrl1: "#{api_root}#{uri_two}"
        )
      end
    end
  end
end
