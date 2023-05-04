require "bcrypt"
require "pry"
require "redcarpet"
require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "yaml"

configure do
  enable :sessions
  set :sessions_secret, 'secret'
  set :erb, :escape_html => true
end

before do
  session[:files] ||= []
end

helpers do
  def render_markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(text)
  end

  def load_file_content(file_path)
    content = File.read(file_path)
    case File.extname(file_path)
    when ".md"
      erb render_markdown(content)
    when ".txt"
      headers["Content-Type"] = "text/plain"
      content
    end
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

def correct_login?(user, pass)
  users = load_user_credentials
  if users.key?(user)
    bcrypt_pass = BCrypt::Password.new(users[user])
    bcrypt_pass == pass
  else
    false
  end
end

def user_signed_in?
  session.key?(:user)
end

def redirect_if_not_signed_in
  unless user_signed_in?
    session[:message] = "You must be signed in to do that"
    redirect "/"
  end
end

root = File.expand_path("..", __FILE__)

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end

  erb :index
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  if correct_login?(params[:user], params[:password])
    session[:user] = params[:user]
    session[:message] = "Welcome #{session[:user].capitalize}!"
    redirect "/"
  else
    @user = params[:user]
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
    session[:user] = nil
    session[:message] = "You have been signed out"

    redirect "/"
end

get "/new" do
  redirect_if_not_signed_in

  erb :new_file
end

def validate_file_name(name)
  name = name.to_s.gsub(" ", "")
  if name[-4..-3].include?(".")
    file, ext = name.split(".")
    if ["md", "txt"].include?(ext) && file.size > 0
      return name
    else
      return "invalid"
    end
  else
    "invalid"
  end
end

post '/create' do
  redirect_if_not_signed_in

  file_name = validate_file_name(params[:new_file])
  file_path = File.join(data_path, file_name)

  if file_name == "invalid"
    session[:message] = "That's not a valid filename. It needs a name and .txt or .md extension"
    status 422
    erb :new_file
  elsif File.file?(file_path)
    session[:message] = "We already have a file called #{file_name}"
    status 422
    erb :new_file
  else
    File.new(file_path, "w")
    session[:message] = "#{file_name} has been created"
    redirect "/"
  end
end

post '/delete' do
  redirect_if_not_signed_in

  file_path = File.join(data_path, params[:delete_file])

  File.delete(file_path)

  session[:message] = "#{params[:delete_file]} has been deleted"
  redirect "/"
end

get "/:file_name" do
  file_path = File.join(data_path, File.basename(params[:file_name]))

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "We don't have a file called #{params[:file_name]}"
    redirect "/"
  end
end

get '/:file_name/edit' do
  redirect_if_not_signed_in

  file_path = File.join(data_path, params[:file_name])

  @file_name = params[:file_name]
  @file = File.read(file_path)

  erb :edit_file
end

post '/:file_name' do
  redirect_if_not_signed_in

  file_path = File.join(data_path, params[:file_name])

  File.write(file_path, params[:new_text])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect "/"
end

