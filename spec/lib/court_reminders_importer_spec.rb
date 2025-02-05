require 'rails_helper'

describe CourtRemindersImporter do
  describe 'self.generate_reminders', active_job: true do
    subject { described_class.generate_reminders(court_dates, court_locs, csv) }
    let(:admin_user) { create :user }
    let(:ctracks) { %w[111 112 113] }
    let(:time_zone_offset) { '-0600' }
    let(:csv) { CourtDateCSV.create!(file: File.new('./spec/fixtures/court_dates.csv'), user: admin_user) }
    let(:court_dates) do
      [
        { 'ofndr_num' => ctracks[0], '(expression)' => '1337D', 'lname' => 'HANES',  'crt_dt' => '5/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' },
        { 'ofndr_num' => ctracks[1], '(expression)' => '8675R', 'lname' => 'SIMON',  'crt_dt' => '5/9/2018', 'crt_tm' => '9:40', 'crt_rm' => '2' },
        { 'ofndr_num' => ctracks[2], '(expression)' => '1776B', 'lname' => 'BARTH',  'crt_dt' => '5/10/2018', 'crt_tm' => '14:30', 'crt_rm' => '3' },
        { 'ofndr_num' => 'not found', '(expression)' => '1776B', 'lname' => 'BARTH', 'crt_dt' => '5/10/2018', 'crt_tm' => '14:30', 'crt_rm' => '3' }
      ]
    end

    let(:court_locs) do
      {
        '1337D' => 'RIVENDALE DISTRICT (444 hobbit lane)',
        '8675R' => 'ROHAN COURT (123 Horse Lord Blvd)',
        '1776B' => 'MORDER COUNTY (666 Doom rd)'
      }
    end

    let!(:rr1) { create :reporting_relationship }
    let!(:rr2) { create :reporting_relationship }
    let!(:rr3) { create :reporting_relationship }
    let!(:rr_irrelevant) { create :reporting_relationship, notes: 'not a ctrack number' }

    before do
      rr1.client.update!(id_number: ctracks[0])
      rr2.client.update!(id_number: ctracks[1], next_court_date_at: Date.new(2018, 5, 12), next_court_date_set_by_user: true)
      rr3.client.update!(id_number: ctracks[2], next_court_date_at: Date.new(2018, 5, 13))
      rr_irrelevant.client.update!(id_number: 91111111111)
      travel_to Time.strptime("5/1/2018 8:30 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
    end

    after do
      travel_back
    end

    it 'schedules messages for relevant reporting relationships' do
      expect(subject).to eq(3)

      expect(rr1.messages.scheduled).to_not be_empty
      body1 = I18n.t(
        'message.auto_court_reminder',
        location: 'RIVENDALE DISTRICT (444 hobbit lane)',
        date: '5/8/2018',
        time: '8:30am',
        room: '1'
      )
      time1 = Time.strptime("5/7/2018 8:30 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
      message1 = rr1.messages.scheduled.last
      expect(rr1.client.reload.next_court_date_at).to eq(Date.new(2018, 5, 8))
      expect(message1.body).to eq body1
      expect(message1.send_at).to eq time1
      expect(message1.court_date_csv).to eq(csv)

      expect(rr2.messages.scheduled).to_not be_empty
      body2 = I18n.t(
        'message.auto_court_reminder',
        location: 'ROHAN COURT (123 Horse Lord Blvd)',
        date: '5/9/2018',
        time: '9:40am',
        room: '2'
      )
      time2 = Time.strptime("5/8/2018 9:40 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
      message2 = rr2.messages.scheduled.last
      expect(rr2.client.reload.next_court_date_at).to eq(Date.new(2018, 5, 12))
      expect(message2.body).to eq body2
      expect(message2.send_at).to eq time2

      expect(rr3.messages.scheduled).to_not be_empty
      body3 = I18n.t(
        'message.auto_court_reminder',
        location: 'MORDER COUNTY (666 Doom rd)',
        date: '5/10/2018',
        time: '2:30pm',
        room: '3'
      )
      time3 = Time.strptime("5/9/2018 14:30 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
      message3 = rr3.messages.scheduled.last
      expect(rr3.client.reload.next_court_date_at).to eq(Date.new(2018, 5, 10))
      expect(message3.body).to eq body3
      expect(message3.send_at).to eq time3

      expect(rr_irrelevant.messages.scheduled).to be_empty
    end

    context 'there is a bad date' do
      let(:court_dates) do
        [
          { 'ofndr_num' => '111', '(expression)' => '1337D', 'lname' => 'HANES', 'crt_dt' => '5/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' },
          { 'ofndr_num' => '112', '(expression)' => '8675R', 'lname' => 'SIMON', 'crt_dt' => '5/42/2018', 'crt_tm' => '9:40', 'crt_rm' => '2' },
          { 'ofndr_num' => '113', '(expression)' => '1776B', 'lname' => 'BARTH', 'crt_dt' => '5/10/2018', 'crt_tm' => '14:30', 'crt_rm' => '3' }
        ]
      end

      let!(:existing_reminder) { create :court_reminder, reporting_relationship: rr1, send_at: Time.zone.now + 2.days, court_date_csv: csv }

      it 'does not save any messages' do
        expect { subject }.to raise_error(ArgumentError, /invalid date or strptime format.*/)

        expect(rr1.messages.scheduled).to contain_exactly(existing_reminder)
        expect(rr2.messages.scheduled).to be_empty
        expect(rr3.messages.scheduled).to be_empty
      end
    end

    context 'there is a nil ofndr_num' do
      let!(:rr_nil_notes) { create :reporting_relationship, notes: nil }
      let(:court_dates) do
        [
          { 'ofndr_num' => nil, '(expression)' => '1337D', 'lname' => 'HANES', 'crt_dt' => '5/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' }
        ]
      end

      it 'does not save any messages' do
        subject
        expect(CourtReminder.all).to be_empty
      end
    end

    context 'there are already court date reminders' do
      let!(:existing_reminder) { create :court_reminder, reporting_relationship: rr1, send_at: Time.zone.now + 2.days, court_date_csv: csv }

      it 'deletes all existing reminders' do
        subject
        expect(rr1.messages.scheduled).to_not include(existing_reminder)
      end
    end

    context 'there are court dates in the past' do
      let(:court_dates) do
        [
          { 'ofndr_num' => ctracks[0], '(expression)' => '1337D', 'lname' => 'HANES',  'crt_dt' => '1/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' },
          { 'ofndr_num' => ctracks[0], '(expression)' => '1337D', 'lname' => 'HANES',  'crt_dt' => '5/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' }
        ]
      end

      it 'ignores past court dates' do
        subject

        first_date = Time.strptime("#{court_dates[0]['crt_dt']} #{court_dates[0]['crt_tm']} #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
        expect(first_date).to be < Time.zone.now

        second_date = Time.strptime("#{court_dates[1]['crt_dt']} #{court_dates[1]['crt_tm']} #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
        expect(second_date).to be > Time.zone.now + 1.day

        expect(rr1.messages.count).to eq 1
      end
    end

    context 'there are court dates less than 24 hours in the future' do
      let(:court_dates) do
        [
          { 'ofndr_num' => ctracks[0], '(expression)' => '1337D', 'lname' => 'HANES',  'crt_dt' => '5/1/2018', 'crt_tm' => '9:00', 'crt_rm' => '1' },
          { 'ofndr_num' => ctracks[0], '(expression)' => '1337D', 'lname' => 'HANES',  'crt_dt' => '5/8/2018', 'crt_tm' => '8:30', 'crt_rm' => '1' }
        ]
      end

      it 'ignores near-future court dates' do
        subject

        first_date = Time.strptime("#{court_dates[0]['crt_dt']} #{court_dates[0]['crt_tm']} #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
        expect(first_date).to be > Time.zone.now
        expect(first_date).to be < Time.zone.now + 1.day

        second_date = Time.strptime("#{court_dates[1]['crt_dt']} #{court_dates[1]['crt_tm']} #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
        expect(second_date).to be > Time.zone.now + 1.day

        expect(rr1.messages.count).to eq 1
      end
    end

    context 'there are two RRs with the same ctrack' do
      let!(:rr4) { create :reporting_relationship }

      before do
        rr4.client.update!(id_number: ctracks[0])
        create :text_message, send_at: Time.zone.now - 1.day, reporting_relationship: rr4
      end

      it 'picks the rr that was most recently contacted' do
        subject

        expect(rr1.messages.scheduled).to be_empty

        expect(rr4.messages.scheduled).to_not be_empty
        body = I18n.t(
          'message.auto_court_reminder',
          location: 'RIVENDALE DISTRICT (444 hobbit lane)',
          date: '5/8/2018',
          time: '8:30am',
          room: '1'
        )
        time = Time.strptime("5/7/2018 8:30 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
        message = rr4.messages.scheduled.last
        expect(message.body).to eq body
        expect(message.send_at).to eq time
      end

      context 'two rrs have both been contacted' do
        before do
          create :text_message, send_at: Time.zone.now - 3.days, reporting_relationship: rr1
          create :text_message, send_at: Time.zone.now - 1.day, reporting_relationship: rr4
        end

        it 'picks the rr that was most recently contacted' do
          subject

          expect(rr1.messages.scheduled).to be_empty

          expect(rr4.messages.scheduled).to_not be_empty
          body = I18n.t(
            'message.auto_court_reminder',
            location: 'RIVENDALE DISTRICT (444 hobbit lane)',
            date: '5/8/2018',
            time: '8:30am',
            room: '1'
          )
          time = Time.strptime("5/7/2018 8:30 #{time_zone_offset}", '%m/%d/%Y %H:%M %z')
          message = rr4.messages.scheduled.last
          expect(message.body).to eq body
          expect(message.send_at).to eq time
        end
      end
    end
  end

  describe 'self.generate_locations_hash' do
    let(:original_court_locs) do
      [
        { 'crt_loc_cd' => '1337D', 'crt_loc_desc' => 'RIVENDALE DISTRICT (444 hobbit lane)' },
        { 'crt_loc_cd' => '8675R', 'crt_loc_desc' => 'ROHAN COURT (123 Horse Lord Blvd)' },
        { 'crt_loc_cd' => '1776B', 'crt_loc_desc' => 'MORDER COUNTY (666 Doom rd)' }
      ]
    end

    let(:expected_court_locs) do
      {
        '1337D' => 'RIVENDALE DISTRICT (444 hobbit lane)',
        '8675R' => 'ROHAN COURT (123 Horse Lord Blvd)',
        '1776B' => 'MORDER COUNTY (666 Doom rd)'
      }
    end

    subject { described_class.generate_locations_hash(original_court_locs) }

    it 'transforms the array into a hash' do
      expect(subject).to eq(expected_court_locs)
    end
  end
end
