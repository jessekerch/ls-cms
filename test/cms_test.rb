ENV["RACK_ENV"] = "test"

require "fileutils"
require "minitest/autorun"
require "pry"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { user: "admin" } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_doc
    create_document "history.txt", "Ruby 0.95 released"

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_viewing_markdown_document
    create_document "about.md", "#This is the About Title..."

    get "/about.md"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>This is the About Title...</h1>"
  end

  def test_nonexistent_file
    get "/notafile.ext"

    assert_equal 302, last_response.status
    assert_equal "We don't have a file called notafile.ext", session[:message]
  end

  def test_editing_document
    create_document "changes.txt", "Ruby 0.95 released"

    get "/changes.txt/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_edit_page_signed_out
    create_document "changes.txt", "Ruby 0.95 released"
    get "/changes.txt/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_updating_document
    create_document "changes.txt", "Ruby 0.95 released"
    post "/changes.txt", {new_text: "some new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "some new content"
  end

  def test_update_doc_signed_out
    create_document "changes.txt", "Ruby 0.95 released"
    post "/changes.txt", new_text: "some new content"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_new_document_page
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "Add a new document"
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_view_new_doc_page_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end

  def test_creating_document
    post "/create", {new_file: "a_new_file.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "a_new_file.txt has been created", session[:message]

    get "/"
    assert_includes last_response.body, "a_new_file.txt"
  end

  def test_creating_doc_no_file_name
    post "/create", {new_file: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "That's not a valid filename. It needs a name and .txt or .md extension"
  end

  def test_deleting_document
    create_document("a_new_file.txt")

    post "/delete", {delete_file: "a_new_file.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "a_new_file.txt has been deleted", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/a_new_file.txt")
  end

  def test_delete_file_signed_out
    create_document("a_new_file.txt")

    post "/delete", delete_file: "a_new_file.txt"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]

    get "/"
    assert_includes last_response.body, "a_new_file.txt"
  end

  def test_user_signin_success
    post "/users/signin", user: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:user]

    get "/"
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_user_signin_fail
    post "/users/signin", user: "invalid", password: "invalid"
    assert_equal 422, last_response.status
    assert_nil session[:user]
    assert_includes last_response.body, "Invalid credentials"
  end

  def test_user_signout
    get "/", {}, { "rack.session" => { user: "admin" } }
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out", session[:message]

    get last_response["Location"]
    assert_nil session[:user]
    assert_includes last_response.body, "Sign In"
  end
end



