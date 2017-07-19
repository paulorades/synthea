module Synthea
  module Output
    module Exporter
      def self.export(patient, end_time = Time.now)
        patient = filter_for_export(patient, end_time) unless Synthea::Config.exporter.years_of_history <= 0

        if Synthea::Config.exporter.ccda.export || Synthea::Config.exporter.ccda.upload || Synthea::Config.exporter.html.export
          ccda_record = Synthea::Output::CcdaRecord.convert_to_ccda(patient, end_time)

          if Synthea::Config.exporter.ccda.export
            out_dir = get_output_folder('CCDA', patient)
            xml = HealthDataStandards::Export::CCDA.new.export(ccda_record)
            out_file = File.join(out_dir, "#{filename(patient)}.xml")
            File.open(out_file, 'w') { |file| file.write(xml) }
          end

          if Synthea::Config.exporter.html.export
            out_dir = get_output_folder('html', patient)
            html = HealthDataStandards::Export::HTML.new.export(ccda_record)
            out_file = File.join(out_dir, "#{filename(patient)}.html")
            File.open(out_file, 'w') { |file| file.write(html) }
          end
        end

        if Synthea::Config.exporter.fhir.export || Synthea::Config.exporter.fhir.upload
          fhir_record = Synthea::Output::FhirRecord.convert_to_fhir(patient, end_time)

          if Synthea::Config.exporter.fhir.upload
            fhir_upload(fhir_record, Synthea::Config.exporter.fhir.upload)
          end

          if Synthea::Config.exporter.fhir.export
            out_dir = get_output_folder('fhir', patient)
            data = fhir_record.to_json
            out_file = File.join(out_dir, "#{filename(patient)}.json")
            File.open(out_file, 'w') { |file| file.write(data) }
          end
        end

        if Synthea::Config.exporter.fhir_dstu2.export
          fhir_record = Synthea::Output::FhirDstu2Record.convert_to_fhir(patient, end_time)
          out_dir = get_output_folder('fhir_dstu2', patient)
          data = fhir_record.to_json
          out_file = File.join(out_dir, "#{filename(patient)}.json")
          File.open(out_file, 'w') { |file| file.write(data) }
        end

        if Synthea::Config.exporter.text.export
          text_record = Synthea::Output::TextRecord. text(patient, end_time)
          out_dir = get_output_folder('text', patient)
          out_file = File.join(out_dir, "#{filename(patient)}.txt")
          File.open(out_file, 'w') { |file| file.write(text_record) }
        end

        if Synthea::Config.exporter.csv.export
          Synthea::Output::CsvRecord.convert_to_csv(patient, end_time)
        end
      end

      def self.filename(patient)
        if Synthea::Config.exporter.use_uuid_filenames
          patient.record_synthea.patient_info[:uuid]
        else
          "#{patient[:name_last]}_#{patient[:name_first]}_#{patient[:age]}"
        end
      end

      def self.get_output_folder(folder_name, patient = nil)
        base = if Synthea::Config.docker.dockerized
                 Synthea::Config.docker.location
               else
                 Synthea::Config.exporter.location
               end
        dirs = [base, folder_name]

        if patient
          dirs << patient[:city] if Synthea::Config.exporter.folder_per_city

          # take the first 2+3 characters of the patient uuid for subfolders
          # uuid = hex so this gives us 256 subfolders, each with 16 sub-subfolders
          if Synthea::Config.exporter.subfolders_by_id_substring
            uuid = patient.record_synthea.patient_info[:uuid]
            dirs << uuid[0, 2]
            dirs << uuid[0, 3]
          end
        end

        folder = File.join(*dirs)

        FileUtils.mkdir_p folder unless File.exist? folder

        folder
      end

      def self.fhir_upload(bundle, fhir_server_url, fhir_client = nil)
        # create a new client object for each upload
        # unless they provide us a client to use
        unless fhir_client
          fhir_client = FHIR::Client.new(fhir_server_url)
          fhir_client.default_format = FHIR::Formats::ResourceFormat::RESOURCE_JSON
        end

        fhir_client.begin_transaction
        bundle.entry.each do |entry|
          # defined our own 'add to transaction' function to preserve our entry information
          add_entry_transaction('POST', nil, entry, fhir_client)
        end
        begin
          reply = fhir_client.end_transaction
          puts "  Error: #{reply.code}" if reply.code != 200
        rescue StandardError => e
          puts "  Error: #{e.message}"
        end
      end

      def self.add_entry_transaction(_method, url, entry = nil, client)
        request = FHIR::Bundle::Entry::Request.new
        request.local_method = 'POST'
        if url.nil? && !entry.resource.nil?
          options = {}
          options[:resource] = entry.resource.class
          options[:id] = entry.resource.id if request.local_method != 'POST'
          request.url = client.resource_url(options)
          request.url = request.url[1..-1] if request.url.starts_with?('/')
        else
          request.url = url
        end
        entry.request = request
        client.transaction_bundle.entry << entry
        entry
      end

      def self.filter_for_export(patient, end_time = Time.now)
        # filter the patient's history to only the last __ years
        # but also include relevant history from before that. Exclude
        # any history that occurs after the specified end_time (typically
        # this is Time.now).

        cutoff_date = end_time - Synthea::Config.exporter.years_of_history.years

        # dup the patient so that we export only the last _ years but the rest still exists, just in case
        patient = patient.dup
        patient.record_synthea = patient.record_synthea.dup

        [:encounters, :conditions, :observations, :procedures, :immunizations, :careplans, :medications].each do |attribute|
          entries = patient.record_synthea.send(attribute).dup

          entries.keep_if { |e| should_keep_entry(e, attribute, patient.record_synthea, cutoff_date, end_time) }

          # If any entries have an end date in the future but are within the cutoff_date,
          # remove the end date but keep the entry (since it's still active).
          entries.each do |e|
            e['stop'] = nil if e['stop'] && e['stop'] > end_time
            e['end_time'] = nil if e['end_time'] && e['end_time'] > end_time
          end

          patient.record_synthea.send("#{attribute}=", entries)
        end

        patient
      end

      def self.should_keep_entry(e, attribute, record, cutoff_date, end_time = Time.now)
        return true if e['time'] > cutoff_date && e['time'] <= end_time # trivial case, when we're within the last __ years

        # if the entry has a stop time, check if the effective date range overlapped the last __ years
        return true if e['stop'] && e['stop'] > cutoff_date

        # - encounters, observations, immunizations are single dates and have no "reason"
        #    so they can only be filtered by the single date
        # - procedures are always listed in "record.present" so they are only filtered by date.
        #    procedures that have "permanent side effects" such as appendectomy, amputation,
        #    should also add a condition code such as "history of ___" (ex 429280009)
        case attribute
        when :medications
          return record.medication_active?(e['type'])
        when :careplans
          return record.careplan_active?(e['type'])
        when :conditions
          return record.present[e['type']] || (e['end_time'] && e['end_time'] > cutoff_date)
        when :encounters
          return (e['type'] == :death_certification) && (e['time'] <= end_time)
        when :observations
          return (e['type'] == :cause_of_death || e['type'] == :death_certificate) && (e['time'] <= end_time)
        end

        false
      end
    end
  end
end
