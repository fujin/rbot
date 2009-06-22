#
# :title: Atlassian plugin for Jira and Confluence SOAP interface
#
# Author:: AJ Christensen <aj@opscode.com>
# Copyright:: (C) 2009 Opscode, Inc
#

require 'rubygems'
require 'jira4r'

class Atlassian < Plugin
  Config.register Config::StringValue.new('atlassian.jira_url',
    :default => "", :requires_restart => true,
    :desc => "The URL for your JIRA instance")
  Config.register Config::StringValue.new('atlassian.jira_username',
    :default => "rbot", :requires_restart => true,
    :desc => "The username for API access")
  Config.register Config::StringValue.new('atlassian.jira_password',
    :default => "changeme", :requires_restart => true,
    :desc => "The password for API access")
  Config.register Config::StringValue.new('atlassian.jira_search_filter',
    :default => "10002", :requires_restart => true,
    :desc => "The search filter to poll for ticket updates")
  Config.register Config::StringValue.new('atlassian.notify_channel',
    :default => "", :requires_restart => true,
    :desc => "The channel to notify when tickets are updated")

  def initializne
    super
    @remote_jira = Jira4R::JiraTool.new(2, @bot.config['atlassian.jira_url'])
    @remote_jira.login @bot.config['atlassian.jira_username'], @bot.config['atlassian.jira_password']
    @issues = []
    @last_updated_times = nil
    @bot.timer.add(60, :start => Time.now, :repeat => true) {
      get_issues_from_filter_with_limit @bot.config['atlassian.jira_search_filter']
      save_last_updated_times
    }
  end

  def help(plugin, topic="")
    case topic
    when ""
      "I watch for JIRA style ticket references and fetch the data for them. e.g.: chef-123"
    when "ticket"
      "Get the details of a ticket back from JIRA, !ticket CHEF-123"
    end
  end
  
  def listen(m)
		return if m.address?	
		return unless m.kind_of?(PrivMessage) && m.public?
		
		m.message.scan(/(\w{4}-\d+)/i).flatten.each do |ticket|
		  debug "fetching issue by key for #{ticket.upcase}"
		  if issue = get_issue_by_key(ticket.upcase)
  			
  			addressee = case m.message
			    when /^(\S+)[:,]/
			      addressee = "#{$1}: "
		      else
		        addressee = "#{m.sourcenick}: "
	      end
	      
        m.reply issue_format(issue)
      end
	  end
	end

  def ticket(m, params)
    if issue = get_issue_by_key(params[:key])
      m.reply issue_format(issue)
    else
      m.reply "could not find ticket #{params[:key]}"
    end
  end

  private 

  def issue_format(issue)
    "#{issue.key} (#{issue.status}/#{issue.priority}): '#{issue.summary}' updated #{time_format(issue.updated)} #{url_format(issue.key)}"
  end
  
  def url_format(key)
    "#{JIRA_URL}/browse/#{key}"
  end

  def format_ticket_compare(ticket_a, ticket_b)

  end
  
  # time_format
  # Attempt to format the date or time.
  # return a pertty string, or the original.
  def time_format(date_or_time)
    date = date_or_time.utc
    now = Time.now.utc

    diff = (now - date).abs
    earlier = now > date
    later = !earlier

    if diff < 1.day && date.day == now.day && earlier
      return 'earlier today'
    elsif diff < 1.day && date.day == now.day && later
      return 'later today'
    elsif diff < 2.days && date.day == (now - 1.day).utc.day
      return 'yesterday'
    elsif diff < 2.days && date.day == (now + 1.day).utc.day
      return 'tomorrow'
    elsif diff < 1.week && date.wday < now.wday && earlier
      return 'earlier this week'
    elsif diff < 1.week && date.wday > now.wday && later
      return 'later this week'
    elsif diff < 1.week && earlier
      return 'last week'
    elsif diff < 1.week && later
      return 'next week'
    elsif diff < 2.weeks && date.wday < now.wday && earlier
      return 'last week'
    elsif diff < 2.weeks && date.wday > now.wday && later
      return 'next week'
    elsif diff < 1.month && date.month == now.month && earlier
      return 'earlier this month'
    elsif diff < 1.month && date.month == now.month && later
      return 'later this month'
    elsif diff < 2.months && date.month == (now - 1.month).utc.month
      return 'last month'
    elsif diff < 2.months && date.month == (now + 1.month).utc.month
      return 'next month'
    elsif diff < 1.year && date.year == now.year && earlier
      return 'earlier this year'
    elsif diff < 1.year && date.year == now.year && later
      return 'later this year'
    elsif diff < 2.years && date.year == (now - 1.year).utc.year
      return 'last year'
    elsif diff < 2.years && date.year == (now + 1.year).utc.year
      return 'next year'
    else
      date_or_time
    end
  end  
    
  def get_issues_from_filter_with_limit(filter="10000")  
    @issues = @remote_jira.getIssuesFromFilter(filter).first(10).map do |i|
      comments = @remote_jira.getComments(i.key.to_s)
      Hash[:issue => i, :comments => comments ]
    end
  end
  
  def get_issue_by_key(key="")
    @remote_jira.getIssue(key)
  end

  def save_last_updated_times
    @last_updated_times ||= Hash.new
    i = @issues.first
    issue_time = i[:issue].updated

    begin
      if issue_time > @last_updated_times[:issue_time] 
        @bot.say @bot.config['atlassian.notify_channel'], format_issue(i[:issue])
        @last_updated_times[:issue_time] = issue_time
      end
    rescue
      nil
    ensure
      @last_updated_times[:issue_time] = issue_time
    end
  end
end

plugin = Atlassian.new
plugin.map "ticket :key", :defaults => { :key => '' }, :requirements => { :key => /[A-Z]+-\d+/ }
