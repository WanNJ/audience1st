require 'application'           # to get String#name_capitalize...ugh....
  
class Visit < ActiveRecord::Base
  belongs_to :customer
  validates_associated :customer
  validates_columns :contact_method, :purpose, :result
  include Enumerable
  include Comparable
  def <=>(other_visit)
    thedate <=> other_visit.thedate
  end

  def name_for(id, default_str="NOT FOUND: %s")
    id.zero? ? "???" :
      begin
        Customer.find(id).full_name
      rescue Exception => e
        logger.error("Lookup customer_id #{id}: #{e.message}")
        sprintf(default_str, e.message)
      end
  end

  def visited_by ;   name_for(visited_by_id) ;  end

  def followup_by ; name_for(followup_assigned_to_id) ; end

  def summarize(arg=:thedate)
    "#{self.visited_by} on #{self.send(arg).to_formatted_s(:short)}"
  end

  # this is a class method because it's called via script/runner from
  # a cron job.  Identify all visits that have a followup due in the next
  # week; group by whose job it is to followup; and send emails.
  def self.notify_pending_followups
    # bug: these should all be configurable variables...
    start = (Time.now + 1.week).at_beginning_of_week
    nd = start + 1.week
    start,nd = Time.now-2.months, Time.now + 2.months
    vs = Visit.find(:all,
                    :conditions => ["followup_date BETWEEN ? AND ?",start,nd],
                    :order => 'followup_date')
    # group them by who's responsible
    vs.group_by(&:followup_assigned_to_id).each_pair do |who,visits|
      w = Customer.find(who)
      #puts "Delivering to #{w.login}:"
      #visits.each { |v| puts "#{v.customer.full_name} on #{v.followup_date.to_s}" }
      deliver_pending_followups(w.login, visits)
    end
  end
  
end