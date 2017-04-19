require_relative '../../test_helper'

class AppendicitisTest < Minitest::Test
  def setup
    @time = Time.new(2017,01,01)
    @patient = Synthea::Person.new
    @patient[:gender] = 'F'
    @patient.events.create(@time - 35.years, :birth, :birth)
    @patient[:age] = 35

    Synthea::MODULES['appendicitis'] = JSON.parse(File.read(File.join(File.expand_path("../../../../lib/generic/modules", __FILE__), 'appendicitis.json')))
    @context = Synthea::Generic::Context.new('appendicitis')
  end

  def teardown
    Synthea::MODULES.clear
  end

  def test_patient_without_appendicitis
    srand 123
    @context.run(@time, @patient)
    @context.run(@time.advance(years: 65), @patient)
    assert !@patient.record_synthea.conditions.detect { |c| c['type'] == :appendicitis }
  end

  def test_patient_with_appendicitis
    srand 9

    @context.run(@time, @patient)
    @context.run(@time.advance(years: 65), @patient)

    assert @patient.record_synthea.conditions.detect { |c| c['type'] == :appendicitis }
    assert @patient.record_synthea.conditions.detect { |c| c['type'] == :history_of_appendectomy }
    assert @patient.record_synthea.encounters.detect { |c| c['type'] == :emergency_room_admission && c['reason'] == :appendicitis }
    assert @patient.record_synthea.encounters.detect { |c| c['type'] == :encounter_inpatient && c['reason'] == :appendicitis }
  end

  def test_patient_with_rupture
    srand 170

    @context.run(@time, @patient)
    @context.run(@time.advance(years: 65), @patient)

    assert @patient.record_synthea.conditions.detect { |c| c['type'] == :appendicitis }
    assert @patient.record_synthea.conditions.detect { |c| c['type'] == :rupture_of_appendix }
    assert @patient.record_synthea.conditions.detect { |c| c['type'] == :history_of_appendectomy }
    assert @patient.record_synthea.encounters.detect { |c| c['type'] == :emergency_room_admission && c['reason'] == :appendicitis }
    assert @patient.record_synthea.encounters.detect { |c| c['type'] == :encounter_inpatient && c['reason'] == :appendicitis }
  end
end
