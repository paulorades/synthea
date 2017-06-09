require 'gruff'
module Synthea
  module World
    class MonteCarlo

      attr_accessor :costs
      attr_accessor :timelines
      attr_accessor :timelines_labels
      attr_accessor :patients
      attr_accessor :records

      attr_accessor :patient_costs
      attr_accessor :opioid_costs
      attr_accessor :overdoses
      attr_accessor :misuse
      attr_accessor :addiction
      attr_accessor :recovery
      attr_accessor :detox

      def initialize
        @start_date = nil
        @end_date = Synthea::Config.end_date
        @time_step = Synthea::Config.time_step
        @costs = Hash.new(0)
        @costs['Overdose'] = 30000.00
        @costs['Inpatient Addiction Treatment (Weekly)'] = 10000.00
        @costs['Encounter Outpatient'] = 200.00
        @costs['Encounter Inpatient'] = 8000.00
        @costs['Encounter Emergency'] = 1000.00
        @costs['Procedure'] = 400.00
        @costs['DiagnosticReport'] = 150.00
        @costs['MedicationRequest'] = 100.00
        @costs['Immunization'] = 100.00
        @patient_costs = []
        @opioid_costs = []
        @timelines = []
        @timelines_labels = []
        @patients = []
        @records = []
        @overdoses = 0
        @misuse = 0
        @addiction = 0
        @recovery = 0
        @detox = 0
        Synthea::Rules.modules # trigger the loading of modules here, to ensure they are set before all threads start
      end

      def run
        puts 'Generating patient...'
        run_random
      end

      def run_random
        # person = build_person while person.nil?
        # retirement_cost = cost_patient(person, @date)
        # log_patient(person, retirement_cost)
        10.times do
          # corpse = go_until_death(person)
          person = build_person
          cost = cost_patient(person, @date)
          log_patient(person, cost)
          @patients << person
          @records << Synthea::Output::TextRecord.convert_to_text(person, @date)
        end
        # render_timelines
      end

      def build_person
        target_age = rand(18..100) #65
        earliest_birthdate = @end_date - (target_age + 1).years + 1.day
        latest_birthdate = @end_date - target_age.years
        @date = rand(earliest_birthdate..latest_birthdate)
        @start_date = @date.dup
        person = Synthea::Person.new
        dead = false
        while @date <= @end_date && !dead
          @date += @time_step.days
          Synthea::Rules.apply(@date, person)
          dead = person.had_event?(:death)
        end
        person
        # if dead
        #   nil
        # else
        #   person
        # end
      end

      def go_until_death(person)
        corpse = Marshal.load(Marshal.dump(person))
        dead = false
        @death_date = @date.dup
        until dead
          @death_date += @time_step.days
          Synthea::Rules.apply(@death_date, corpse)
          dead = corpse.had_event?(:death)
        end
        corpse
      end

      def log_patient(person, cost)
        od = person[:generic]['opioid_addiction'].history.select{|x| x.name=='Directed_Use_Overdose'}.count
        od += person[:generic]['opioid_addiction'].history.select{|x| x.name=='Misuse_Overdose'}.count
        od += person[:generic]['opioid_addiction'].history.select{|x| x.name=='Addiction_Overdose'}.count
        mu = person[:generic]['opioid_addiction'].history.select{|x| x.name=='Misuse'}.count
        ad = person[:generic]['opioid_addiction'].history.select{|x| x.name=='Active_Addiction'}.count
        rc = person[:generic]['opioid_addiction'].history.select{|x| x.name=='Recovery_Management'}.count
        dt = person[:generic]['opioid_addiction'].history.select{|x| x.name=='Enter_Addiction_Treatment'}.count

        @opioid_costs << (od * @costs['Overdose']) + (dt * @costs['Addiction Treatment (Weekly)'])
        @overdoses += od
        @misuse += mu
        @addiction += ad
        @recovery += rc
        @detox += dt

        str = ''
        str << timestamp << ' : '
        str << "#{person[:name_last]}, #{person[:name_first]}. #{person[:race].to_s.capitalize} #{person[:ethnicity].to_s.tr('_', ' ').capitalize}. #{person[:age]} y/o #{person[:gender]}"

        weight = (person.get_vital_sign_value(:weight) * 2.20462).to_i
        active_conditions = []
        person.record_synthea.conditions.select { |c| c['end_time'].nil? }.each { |c| active_conditions << c['type'] }

        str << " #{weight} lbs. -- #{active_conditions.uniq.join(', ')}"
        str << " : $#{cost}"
        @timelines_labels << str
        puts str
      end

      def timestamp
        Time.now.strftime('[%F %T]')
      end

      def cost_patient(person, end_time)
        record = Synthea::Output::FhirRecord.convert_to_fhir(person, end_time)
        cost = 0.00
        timeline = {}
        record.entry.each do |entry|
          resource = entry.resource
          price = @costs[resource.resourceType]
          if resource.resourceType == 'Encounter'
            if resource.local_class.code == 'inpatient' || resource.type.first.text.downcase.include?('inpatient')
              price = @costs['Encounter Inpatient']
            elsif resource.local_class.code == 'emergency' || resource.type.first.text.downcase.include?('emergency')
              price = @costs['Encounter Emergency']
            else
              price = @costs['Encounter Outpatient']
            end
          end
          price *= resource.dispenseRequest.numberOfRepeatsAllowed if resource.is_a?(FHIR::MedicationRequest) && resource.dispenseRequest && resource.dispenseRequest.numberOfRepeatsAllowed
          cost += price
          # add point to timeline
          date_time = Synthea::Output::FhirRecord.get_date_time(resource)
          if price > 0 && date_time
            time_step_x = (date_time - @start_date) / @time_step.days
            timeline[time_step_x.to_i] = cost
          end
        end
        @timelines << timeline
        @patient_costs << cost
        cost
      end

      def render_timelines(filename = 'output/linegraph.png')
        puts "Generating #{filename}..."
        graph = Gruff::Line.new
        graph.title = 'Monte Carlo Patient Simulation'
        graph.hide_dots = true
        graph.hide_legend = true
        graph.line_width = 1.0
        @timelines.each_with_index do |timeline, index|
          xpoints = []
          ypoints = []
          timeline.each do |time, cost|
            xpoints << time
            ypoints << cost
          end
          graph.dataxy(index, xpoints, ypoints)
        end
        graph.write(filename)
      end
    end
  end
end
