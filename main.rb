#!/usr/bin/ruby

require 'net/http'
require 'net/https'
require 'json'
require "csv"
require "base64"

puts "Enter Your Jamf Cloud Instance Name."
@instance_name = gets.strip
puts "Enter Your Jamf Cloud Username."
@username = gets.strip
puts "Enter Your Jamf Cloud Password."
@password = gets.strip
puts "Enter Computer Serial Number"
@computer_serial_number = gets.strip

# /uapi/auth/tokens (POST )
def get_token
	uri = URI("https://#{@instance_name}.jamfcloud.com/uapi/auth/tokens")
	
	# Create client
	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_PEER
	
	# Create Request
	req = Net::HTTP::Post.new(uri)
	crendential = 'Basic ' + Base64.encode64("#{@username}:#{@password}").strip
	
	# Add headers
	req.add_field "authorization", crendential
	
	# Fetch Request
	res = http.request(req)
	puts "Response HTTP Status Code: #{res.code}"
	json = JSON.parse(res.body)
	json["token"]
rescue StandardError => e
	puts "HTTP Request failed (#{e.message})"
end

def fetch_computers(current_page=0)
	page_size = 100
	uri = URI("https://#{@instance_name}.jamfcloud.com/api/preview/computers?page=#{current_page}&page-size=#{page_size}")
	puts uri
	# Create client
	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_PEER
	
	# Create Request
	req =  Net::HTTP::Get.new(uri)
	# Add headers
	req.add_field "Authorization", "Bearer #{get_token}"
	
	# Fetch Request
	res = http.request(req)
	json = JSON.parse(res.body)
	total_count = json["totalCount"]
	puts max_page = (total_count / page_size)+1
	json["results"].each { |result|
		serial_number = result["serialNumber"]
		management_id = result["managementId"]
		if !serial_number_exist?(serial_number)
			add_row(serial_number, management_id)
		end
	}
	if current_page < max_page -1
		fetch_computers(current_page+1)
	end
rescue StandardError => e
	puts "HTTP Request failed (#{e.message})"
end

def rebuild_kernel_cache_and_restart(management_id)
	uri = URI("https://#{@instance_name}.jamfcloud.com/api/preview/mdm/commands")
	
	# Create client
	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_PEER
	dict = {
						"clientData" => [
								{
										"managementId" => "#{management_id}",
										"clientType" => "COMPUTER"
								}
						],
						"commandData" => {
								"notifyUser" => "true",
								"commandType" => "RESTART_DEVICE",
								"rebuildKernelCache" => "true"
						}
				}
	body = JSON.dump(dict)
	
	# Create Request
	req =  Net::HTTP::Post.new(uri)
	# Add headers
	req.add_field "authorization", "Bearer #{get_token}"
	# Add headers
	req.add_field "Content-Type", "application/json"
	
	# Set body
	req.body = body
	puts body
	# Fetch Request
#	res = http.request(req)
#	puts "Response HTTP Status Code: #{res.code}"
#	puts "Response HTTP Response Body: #{res.body}"
rescue StandardError => e
	puts "HTTP Request failed (#{e.message})"
end

def create_csv
	headers = ["serial_number","management_id"]
	CSV.open('computers.csv', 'a+') do |row|
	row << headers
	end
end

def add_row(serial_number, management_id)
	if(!File.exist?('computers.csv'))
		create_csv
	end
	CSV.open('computers.csv', 'a+') do |row|
	row << [serial_number,management_id]
	end
end

def select_management_id_of(serial_number)
	csv = CSV.read('computers.csv', headers: true )
	row = csv.find { |row| row['serial_number'] == serial_number }
	row["management_id"]
end

def serial_number_exist?(serial_number)
	if(!File.exist?('computers.csv'))
		create_csv
	end
	csv = CSV.read('computers.csv', headers: true )
	row = csv.find { |row| row['serial_number'] == serial_number }
	!row.nil?
end

fetch_computers
serial_number = select_management_id_of(@computer_serial_number)
rebuild_kernel_cache_and_restart(serial_number)
