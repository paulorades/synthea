module Synthea
  module Tasks
    class Metrics

      def self.run_single_module(module_file, options = {})
        puts "Calculating stats for #{module_file}"
        module_json = JSON.parse(File.read(module_file))
        population = options[:population] || Synthea::Config.sequential.population

        start_date = options[:start_date] || Synthea::Config.start_date
        end_date = options[:end_date] || Synthea::Config.end_date

        lifecycle = Synthea::Modules::Lifecycle.new 

        # key for stats = state name, values = #s going FROM the given state
        stats = Hash.new { |h, k| h[k] = { entered: 0,  # number of times this state was entered
                                           duration: 0, # total length of time people sat in this state
                                           population: 0, # number of people that ever his this state
                                           current: 0, # number of people that are "currently" in that state
                                           destinations: Hash.new { |dh, dk| dh[dk] = 0 } } }

        person_options = options[:person] || {}
        random_options = options[:randomize] || {}

        start_timestamp = Time.now
        population.times do |i|
          person = Synthea::Person.new

          person_options.each { |k, v| person[k] = v }

          context = Synthea::Generic::Context.new(module_json)
          person[:generic] = { context.config['name'] => context }

          lifecycle.run(start_date, person) # give them stuff assigned at birth

          puts "#{(100.0 * i.to_f / population).round(0)}% complete" if i % (population / 10) == 0
          # report progress every 10 percent, whatever the actual population size being run

          date = random_options[:birth_date] ? rand(start_date..end_date) : start_date 

          while !person.had_event?(:death, date) && date <= end_date
            context.run(date, person)
            new_date = exit_time(context.current_state, person, date)
            break if new_date.nil?
            date = new_date
          end

          record_stats(context, stats, date)
        end

        puts "Completed #{population} population in #{Time.now - start_timestamp}"
        
        stats.each { |state, state_stats| print_stats(state, state_stats, module_json, population) }

        unreached = module_json['states'].keys - stats.keys
        unreached.each do |state|
          puts "#{state}: \n Never reached \n\n"
        end
      end

      def self.record_stats(context, stats, end_date)
        context.history << context.current_state
        context.history.each { |s| count_state_stats(s, stats[s.name], end_date) }
        context.history.collect(&:name).uniq.each { |n| stats[n][:population] += 1 } # count this person once for each state they hit
        stats[context.current_state.name][:current] += 1 # count the state they are currently in
        context.transition_counts.each do |from_state, destinations|
          destinations.each do |to_state, count|
            stats[from_state][:destinations][to_state] += count
          end
        end
      end

      def self.print_stats(state, state_stats, module_json, population)
        puts "#{state}:"
        puts " Total times entered: #{state_stats[:entered]} (does not include transitions looping directly back in)"
        puts " Population that ever hit this state: #{state_stats[:population]} (#{ percent(state_stats[:population], population) } %)"
        puts " Average # of hits per total population: #{(state_stats[:entered].to_f / population).round(2)}"
        puts " Average # of hits per person that ever hit state: #{(state_stats[:entered].to_f / state_stats[:population]).round(2)}"
        puts " Population currently in state: #{state_stats[:current]} ( #{ percent(state_stats[:current],population) } %)"
        state_type = module_json['states'][state]['type']
        if %w(Guard Delay).include?(state_type)
          puts " Total duration: #{duration(state_stats[:duration])}"
          puts " Average duration per time entered: #{duration(state_stats[:duration] / state_stats[:entered])}"
          puts " Average duration per person that ever entered state: #{duration(state_stats[:duration] / state_stats[:population])}"
          # puts " Average duration per entire population: #{duration(state_stats[:duration] / population)}"
        elsif state_type == 'Encounter' && module_json['states'][state]['wellness']
          puts ' (duration metrics for wellness encounter omitted)'
        end
        unless state_stats[:destinations].empty?
          puts " Transitioned to:"
          total_transitions = state_stats[:destinations].values.sum
          state_stats[:destinations].each do |to_state, count|
            puts " --> #{to_state} : #{count} = #{ percent(count.to_f, total_transitions.to_f) }%"
          end
        end
        puts ''
      end

      def self.percent(num, denom, decimal_places = 2)
        (100.0 * num / denom).round(decimal_places)
      end

      def self.duration(time)
        # augmented version of http://stackoverflow.com/a/1679963
        # note that anything less than days here is generally never going to be used
        secs = time
        mins = secs / 60.0
        hours = mins / 60.0
        days = hours / 24.0
        weeks = days / 7.0
        months = days / 30.0 # 365.25 / 12 = 30.4375, but ActiveSupport uses 30 so...
        years = days / 365.25 

        # note: float.to_i truncates, float.round(0) rounds to nearest integer
        if years.to_i > 0
          "#{years.round(2)} years (About #{years.to_i} years and #{months.round(0) % 12} months)"
        elsif months.to_i > 0 
          "#{months.round(2)} months (About #{months.to_i} months and #{days.round(0) % 30} days)"
        elsif weeks.to_i > 0
          "#{weeks.round(2)} weeks (About #{weeks.to_i} weeks and #{days.round(0) % 7} days)"
        elsif days.to_i > 0
          "#{days.round(2)} days (About #{days.to_i} days and #{hours.round(0) % 24} hours)"
        elsif hours.to_i > 0
          "#{hours.round(2)} hours (About #{hours.to_i} hours and #{mins.round(0) % 60} mins)"
        elsif mins.to_i > 0
          "#{mins.round(2)} minutes (About #{mins.to_i} minutes and #{secs.round(0) % 60} seconds)"
        elsif secs.to_i > 0
          "#{secs} seconds"
        else
          "0"
        end
      end

      def self.count_state_stats(state, state_stats, default_end_date)
        state_stats[:entered] += 1
        exit_time = state.exited || default_end_date # if they were in the last state when they died or time expired
        start_time = state.entered || exit_time # hack for when the lifecycle module killed them before they even hit the initial state,
                                                # will add 0 to the total duration in that case
        state_stats[:duration] += (exit_time - start_time)
      end

      # represents the time that the person will exit the given state
      # currently this assumes a single module running standalone
      # such that if a guard allows on some condition from another module
      # this logic will assume that condition is never met
      def self.exit_time(state, person, time)
        case state
        when Synthea::Generic::States::Delay
          return state.expiration # jump ahead to when the delay expires
        when Synthea::Generic::States::Guard
          logic = state.allow
          case logic
          when Synthea::Generic::Logic::Age
            birthdate = person.event(:birth).time
            age = Synthea::Modules::Lifecycle.age(time, birthdate, nil, logic.unit.to_sym)
            return nil if age > logic.quantity && (logic.operator == '<=' || logic.operator == '<')
            diff = logic.quantity - age
            return time + diff.send(logic.unit)
          when Synthea::Generic::Logic::Date
            return nil if time.year > logic.year && (logic.operator == '<=' || logic.operator == '<')
            # the target year already passed so this guard will never allow

            return Time.new(logic.year) # midnight on jan 1st, whatever year
          else
            return nil # assume for simplicity this guard will never allow the person through
          end
        when Synthea::Generic::States::Encounter
          time += rand(0.years..2.years)
          # this is highly simplified but shouldn't affect the results much
          # as long as we don't use wellness encounters expecting a specific amt of delay

          state.perform_encounter(time, person, false) # simulate the wellness encounter
          return time
        when Synthea::Generic::States::Terminal
          return nil
        else
          raise "Ended in unexpected state: #{state}"
        end
      end

    end
  end
end
