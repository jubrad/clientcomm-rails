# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2018_09_21_232040) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "attachments", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "media_file_name"
    t.string "media_content_type"
    t.bigint "media_file_size"
    t.datetime "media_updated_at"
    t.string "dimensions"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "change_images", force: :cascade do |t|
    t.string "file_file_name"
    t.string "file_content_type"
    t.bigint "file_file_size"
    t.datetime "file_updated_at"
    t.bigint "user_id"
    t.index ["user_id"], name: "index_change_images_on_user_id"
  end

  create_table "client_statuses", force: :cascade do |t|
    t.string "name", null: false
    t.integer "followup_date"
    t.string "icon_color", limit: 7
    t.bigint "department_id"
    t.index ["department_id"], name: "index_client_statuses_on_department_id"
  end

  create_table "clients", id: :serial, force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "phone_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.bigint "node_client_id"
    t.bigint "node_comm_id"
    t.string "id_number"
    t.date "next_court_date_at"
    t.boolean "next_court_date_set_by_user", default: false
    t.index ["phone_number"], name: "index_clients_on_phone_number", unique: true
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "court_date_csvs", force: :cascade do |t|
    t.string "file_file_name"
    t.string "file_content_type"
    t.bigint "file_file_size"
    t.datetime "file_updated_at"
    t.bigint "user_id"
    t.index ["user_id"], name: "index_court_date_csvs_on_user_id"
  end

  create_table "delayed_jobs", id: :serial, force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "cron"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "departments", force: :cascade do |t|
    t.string "name"
    t.string "phone_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.text "unclaimed_response"
    t.index ["user_id"], name: "index_departments_on_user_id"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "flag"
    t.boolean "enabled", null: false
  end

  create_table "highlight_blobs", force: :cascade do |t|
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.string "body", default: ""
    t.string "number_from"
    t.string "number_to"
    t.boolean "inbound", default: false, null: false
    t.string "twilio_sid"
    t.string "twilio_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "read", default: false
    t.datetime "send_at", null: false
    t.boolean "sent", default: false
    t.string "last_twilio_update"
    t.bigint "reporting_relationship_id"
    t.bigint "original_reporting_relationship_id", null: false
    t.string "type", null: false
    t.bigint "like_message_id"
    t.bigint "court_date_csv_id"
    t.index ["court_date_csv_id"], name: "index_messages_on_court_date_csv_id"
    t.index ["like_message_id"], name: "index_messages_on_like_message_id"
    t.index ["original_reporting_relationship_id"], name: "index_messages_on_original_reporting_relationship_id"
    t.index ["reporting_relationship_id"], name: "index_messages_on_reporting_relationship_id"
    t.index ["send_at"], name: "index_messages_on_send_at"
    t.index ["twilio_sid"], name: "index_messages_on_twilio_sid"
    t.index ["type"], name: "index_messages_on_type"
  end

  create_table "reporting_relationships", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "last_contacted_at"
    t.boolean "has_unread_messages", default: false, null: false
    t.boolean "has_message_error", default: false, null: false
    t.bigint "client_status_id"
    t.string "category", default: "no_cat"
    t.index ["client_id", "user_id"], name: "index_reporting_relationships_on_client_id_and_user_id"
    t.index ["client_id"], name: "index_reporting_relationships_on_client_id"
    t.index ["client_status_id"], name: "index_reporting_relationships_on_client_status_id"
    t.index ["user_id"], name: "index_reporting_relationships_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.string "email", null: false
    t.bigint "department_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["department_id"], name: "index_reports_on_department_id"
  end

  create_table "survey_questions", force: :cascade do |t|
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "survey_response_links", force: :cascade do |t|
    t.bigint "survey_id"
    t.bigint "survey_response_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["survey_id"], name: "index_survey_response_links_on_survey_id"
    t.index ["survey_response_id"], name: "index_survey_response_links_on_survey_response_id"
  end

  create_table "survey_responses", force: :cascade do |t|
    t.text "text"
    t.bigint "survey_question_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["survey_question_id"], name: "index_survey_responses_on_survey_question_id"
  end

  create_table "surveys", force: :cascade do |t|
    t.bigint "client_id"
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_surveys_on_client_id"
    t.index ["user_id"], name: "index_surveys_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name", null: false
    t.boolean "message_notification_emails", default: true
    t.boolean "active", default: true, null: false
    t.string "phone_number"
    t.bigint "department_id"
    t.string "treatment_group"
    t.bigint "node_id"
    t.boolean "has_unread_messages", default: false, null: false
    t.boolean "admin", default: false
    t.index ["department_id"], name: "index_users_on_department_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "attachments", "messages"
  add_foreign_key "change_images", "users"
  add_foreign_key "clients", "users"
  add_foreign_key "court_date_csvs", "users"
  add_foreign_key "departments", "users"
  add_foreign_key "messages", "court_date_csvs"
  add_foreign_key "messages", "messages", column: "like_message_id"
  add_foreign_key "messages", "reporting_relationships"
  add_foreign_key "messages", "reporting_relationships", column: "original_reporting_relationship_id"
  add_foreign_key "reporting_relationships", "client_statuses"
  add_foreign_key "reporting_relationships", "clients"
  add_foreign_key "reporting_relationships", "users"
  add_foreign_key "reports", "departments"
  add_foreign_key "survey_response_links", "survey_responses"
  add_foreign_key "survey_response_links", "surveys"
  add_foreign_key "survey_responses", "survey_questions"
  add_foreign_key "surveys", "clients"
  add_foreign_key "surveys", "users"
  add_foreign_key "users", "departments"
end
