require "net/http"
require "uri"
require "json"
require "logger"
require "csv"

class CoreError
  KeycloakUrlNotSet = Class.new(StandardError)
  KeycloakRelmNotSet = Class.new(StandardError)
  KeycloakUsernameNotSet = Class.new(StandardError)
  KeycloakPasswordNotSet = Class.new(StandardError)
  KeycloakGrantTypeNotSet = Class.new(StandardError)
  KeycloakClientIDNotSet = Class.new(StandardError)
  KeycloakFailedToGetAccessToken = Class.new(StandardError)
  KeycloakInvalidAccessTokenResponse = Class.new(StandardError)
  KeycloakAccessTokenNotInResponse = Class.new(StandardError)
  KeycloakInvalidCreateClientIDResponse = Class.new(StandardError)
  KeycloakInvalidSetPasswordResponse = Class.new(StandardError)
end

class Keycloak
  def initialize(log, url, relm, username, password, grant_type, client_id)
    @log = log
    @url = url
    @relm = relm
    @username = username
    @password = password
    @grant_type = grant_type
    @client_id = client_id
    @access_token = ""
    validate()
  end

  def validate()
    if "#{@url}" == ""
      @log.error("keycloak url must be set")
      raise CoreError::KeycloakUrlNotSet
    end
    if "#{@relm}" == ""
      @log.error("keycloak relm must be set")
      raise CoreError::KeycloakRelmNotSet
    end
    if "#{@username}" == ""
      @log.error("keycloak username must be set")
      raise CoreError::KeycloakUsernameNotSet
    end
    if "#{@password}" == ""
      @log.error("keycloak password must be set")
      raise CoreError::KeycloakPasswordNotSet
    end
    if "#{@grant_type}" == ""
      @log.error("keycloak grant type must be set")
      raise CoreError::KeycloakGrantTypeNotSet
    end

    if "#{@client_id}" == ""
      @log.error("keycloak client id must be set")
      raise CoreError::KeycloakClientIDNotSet
    end
  end

  def access_token()
    return @access_token
  end

  def set_user_password(relm, username, password)
    userid = get_user_id(relm, username)
    @log.info("set user password  #{username} in relm: #{relm}")
    doc = {
      type: "password",
      temporary: false,
      value: password,
    }.to_json

    uri = URI.parse("#{@url}/admin/realms/#{relm}/users/#{userid}/reset-password")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    header = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@access_token}" }

    request = Net::HTTP::Put.new(uri.request_uri, header)
    request.body = doc

    response = http.request(request)
    result_json = response.body
    puts(result_json)
    if response.code != "204"
      @log.info("Got unexpected response code: #{response.code}")
      @log.info(result_json)
      raise CoreError::KeycloakInvalidSetPasswordResponse
      exit(1)
    end
    return userid
  end

  def create_user(relm, username, password, email, firstname, lastname)
    @log.info("create user #{username} in relm: #{relm}")
    doc = {
      username: username,
      enabled: true,
      email: email,
      firstName: firstname,
      lastName: lastname,

    }.to_json

    uri = URI.parse("#{@url}/admin/realms/#{relm}/users")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    header = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@access_token}" }

    request = Net::HTTP::Post.new(uri.request_uri, header)
    request.body = doc

    response = http.request(request)
    result_json = response.body
    puts(result_json)
    if response.code != "201"
      @log.info("Got unexpected response code: #{response.code}")
      @log.info(result_json)
      raise CoreError::KeycloakInvalidCreateClientIDResponse
      exit(1)
    end
    return set_user_password(relm, username, password)
  end

  def get_user_id(relm, username)
    @log.info("get user #{username} in relm: #{relm}")

    uri = URI.parse("#{@url}/admin/realms/#{relm}/users?username=#{username}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    header = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@access_token}" }
    request = Net::HTTP::Get.new(uri.request_uri, header)
    #request.body = doc
    response = http.request(request)
    result_json = response.body
    res_hash = JSON.parse(result_json)

    if response.code != "200"
      @log.info("Got unexpected response code: #{response.code}")
      @log.info(result_json)
      raise CoreError::KeycloakInvalidCreateClientIDResponse
      exit(1)
    end
    return res_hash[0]["id"]
  end

  def create_client_id(relm, client_id, root_url, admin_url)
    @log.info("create client id in relm: #{relm}")
    doc = {
      clientId: client_id,
      rootUrl: root_url,
      adminUrl: admin_url,
    }.to_json

    uri = URI.parse("#{@url}/admin/realms/#{relm}/clients")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    header = { "Content-Type" => "application/json", "Authorization" => "Bearer #{@access_token}" }

    request = Net::HTTP::Post.new(uri.request_uri, header)
    request.body = doc

    response = http.request(request)
    result_json = response.body
    if response.code != "201"
      @log.info("Got unexpected response code: #{response.code}")
      @log.info(result_json)
      raise CoreError::KeycloakInvalidCreateClientIDResponse
      exit(1)
    end
  end

  def get_access_token()
    @log.info("get access token from keycloak #{@url}")
    u = "#{@url}/realms/#{@relm}/protocol/openid-connect/token"
    uri = URI.parse(u)

    header = { 'Content-Type': "application/x-www-form-urlencoded" }
    body = {
      username: @username,
      password: @password,
      grant_type: @grant_type,
      client_id: @client_id,
    }
    j = body.to_json

    # Create the HTTP objects
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri, header)
    request.set_form_data(body)

    response = http.request(request)
    result_json = response.body
    if response.code != "200"
      @log.info("Got unexpected response code: #{response.code}")
      raise CoreError::KeycloakFailedToGetAccessToken
    end
    if valid_json?(result_json) == false
      raise CoreError::KeycloakInvalidAccessTokenResponse
    end
    data = JSON.parse(result_json)

    if data.has_key?("access_token") == false
      raise CoreError::KeycloakAccessTokenNotInResponse
    end
    @access_token = data["access_token"]
  end

  def valid_json?(json)
    JSON.parse(json)
    true
  rescue JSON::ParserError, TypeError => e
    false
  end
end

def get_env(name, default)
  if "#{ENV[name]}" == ""
    return default
  end
  return ENV[name]
end

def exec(cmd)
  puts(cmd)
  puts(`#{cmd}`)
end

CORE_HOST = get_env("CORE_HOST", "")
CORE_URL = "https://#{CORE_HOST}"
KEYCLOAK_HOST = "keycloak.#{CORE_HOST}"
KEYCLOAK_URL = "https://#{KEYCLOAK_HOST}"
RELM = get_env("RELM", "master")
KEYCLOAK_ADMIN_USER = get_env("KEYCLOAK_ADMIN_USER", "user")
KEYCLOAK_ADMIN_PASSWORD = get_env("KEYCLOAK_ADMIN_PASSWORD", "notset")
KEYCLOAK_ADMIN_CLIENT_ID = get_env("KEYCLOAK_ADMIN_CLIENT_ID", "admin-cli")
NEOS_RELM = get_env("NEOS_RELM", "neos")

NEOS_ADMIN_USER = get_env("NEOS_ADMIN_USER", "neosadmin")
NEOS_ADMIN_PASSWORD = get_env("NEOS_ADMIN_PASSWORD", "notset")
NEOS_PROFILE_NAME = get_env("NEOS_PROFILE_NAME", "neosadmin")

USER_CSV = get_env("USER_CSV", "users.csv")

policy = %{
  {
    "policy": {
      "statements": [
        {
          "action": [
            "*"
          ],
          "condition": [],
          "effect": "allow",
          "principal": [
            "%PRINCIPAL%"
          ],
          "resource": [
            "*"
          ],
          "sid": "SID_SUPERADMIN"
        }
      ],
      "version": "2022-10-01"
    },
    "user": "%PRINCIPAL%"
  }
}

task :display do
  puts("CORE_URL: #{CORE_URL}")
  puts("KEYCLOAK_URL: #{KEYCLOAK_URL}")
  puts("KEYCLOAK_ADMIN_USER: #{KEYCLOAK_ADMIN_USER}")
  puts("USER_CSV: #{USER_CSV}")
end

task :default do
  puts("foo")
end

task :upload_dp do
  puts("upload data products")
  ENV['NEOS_PROFILE_NAME']=NEOS_PROFILE_NAME
  ENV['CORE_HOST']=CORE_HOST
  ENV['NEOS_ADMIN_USER']=NEOS_ADMIN_USER
  Dir.chdir("data-products") {
    exec("./upload.sh")
  }
end

task :create_users do
  log = Logger.new(STDOUT)
  grant_type = "password"

  keycloak = Keycloak.new(log, KEYCLOAK_URL, RELM, KEYCLOAK_ADMIN_USER, KEYCLOAK_ADMIN_PASSWORD, grant_type, KEYCLOAK_ADMIN_CLIENT_ID)
  result = keycloak.get_access_token()
  if result == false
    log("try getting access token again")
    result = keycloak.get_access_token()
  end

  relm = "neos"

  user_list = CSV.open(USER_CSV, headers: :first_row).map(&:to_h)

  user_list.each do |u|
    userid = keycloak.create_user(relm, u["username"], u["password"], u["email"], u["firstname"], u["lastname"])

    exec("neosctl -p #{NEOS_PROFILE_NAME} profile init -h #{CORE_URL} --non-interactive -u #{NEOS_ADMIN_USER}")
    exec("neosctl -p #{NEOS_PROFILE_NAME} auth login -p '#{NEOS_ADMIN_PASSWORD}'")

    policy_doc = policy.gsub("%PRINCIPAL%", userid)
    #puts(policy_doc)
    File.write("/tmp/policy.json", policy_doc)

    exec("neosctl -p #{NEOS_PROFILE_NAME} iam create /tmp/policy.json")
  end
end

task :load_data_products do
end
