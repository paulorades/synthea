require_relative '../test_helper'

class MarshalingTest < Minitest::Test
  def setup
    Synthea::Rules.modules # trigger loading all the modules
  end

  def test_marshaling_event
    event = Synthea::Event.new(Time.now, :marshal, :test_marshaling_event, false)
    clone = Marshal.load(Marshal.dump(event))
    event.processed = true
    assert(!clone.processed)
  end

  def test_marshaling_event_list
    list = Synthea::EventList.new
    list.create(10,:foo,:test_marshaling_event_list)
    list.create(30,:foo,:test_marshaling_event_list)
    list.create(50,:foo,:test_marshaling_event_list)
    list.create(100,:foo,:test_marshaling_event_list)
    list.create(150,:foo,:test_marshaling_event_list)
    clone = Marshal.load(Marshal.dump(list))
    list.unprocessed.each do |event|
      list.process(event)
    end
    assert(clone.unprocessed.length==5)
  end

  def test_marshaling_entity
    entity = Synthea::Entity.new
    entity[:test_attribute] = 42
    entity.events.create(42,:foo,:test_marshaling_entity)
    entity.set_vital_sign(:height, 42, 'cm')
    entity.set_symptom_value(:test, :headache, 42)
    clone = Marshal.load(Marshal.dump(entity))
    entity[:test_attribute] = 50
    entity.events.create(50,:bar,:test_marshaling_entity)
    entity.set_vital_sign(:height, 50, 'cm')
    entity.set_symptom_value(:test, :headache, 50)
    assert(clone[:test_attribute] != entity[:test_attribute])
    assert(!clone.had_event?(:bar))
    assert(clone.get_vital_sign_value(:height) != entity.get_vital_sign_value(:height))
    assert(clone.get_symptom_value(:headache) != entity.get_symptom_value(:headache))
  end

  def test_marshaling_person
    person = Synthea::Person.new
    person[:test_attribute] = 42
    person.events.create(42,:foo,:test_marshaling_person)
    person.set_vital_sign(:height, 42, 'cm')
    person.set_symptom_value(:test, :headache, 42)
    clone = Marshal.load(Marshal.dump(person))
    person[:test_attribute] = 50
    person.events.create(50,:bar,:test_marshaling_person)
    person.set_vital_sign(:height, 50, 'cm')
    person.set_symptom_value(:test, :headache, 50)
    person.record_synthea.death(Time.now)
    assert(clone[:test_attribute] != person[:test_attribute])
    assert(!clone.had_event?(:bar))
    assert(clone.get_vital_sign_value(:height) != person.get_vital_sign_value(:height))
    assert(clone.get_symptom_value(:headache) != person.get_symptom_value(:headache))
    assert(clone.record_synthea.patient_info[:deathdate].nil?)
  end

  def test_marshaling_person_with_modules
    Synthea::Rules.modules # trigger loading all the modules
    person = Synthea::Person.new
    @date = Time.now
    Synthea::Rules.apply(@date, person)
    clone = Marshal.load(Marshal.dump(person))
    @time_step = Synthea::Config.time_step
    @date += @time_step.days
    Synthea::Rules.apply(@date, clone)
    compare_person_and_clone(person, clone)
  end

  def test_marshaling_person_with_modules_repeat
    Synthea::Rules.modules # trigger loading all the modules
    person = Synthea::Person.new
    @date = Time.now
    time_step = Synthea::Config.time_step
    (400 / time_step).times do
      Synthea::Rules.apply(@date, person)
      @date += time_step.days
    end
    # First clone
    first_clone = Marshal.load(Marshal.dump(person))
    @first_clone_date = @date.dup
    (400 / time_step).times do
      Synthea::Rules.apply(@first_clone_date, first_clone)
      @first_clone_date += time_step.days
    end
    compare_person_and_clone(person, first_clone)

    # Second clone
    second_clone = Marshal.load(Marshal.dump(person))
    @second_clone_date = @date.dup
    (400 / time_step).times do
      Synthea::Rules.apply(@second_clone_date, second_clone)
      @second_clone_date += time_step.days
    end
    compare_person_and_clone(person, second_clone)
  end

  def compare_person_and_clone(person, clone)
    # Look for differences in the attributes
    found_diff = false
    clone.attributes[:vital_signs].each do |key, vital|
      if vital[:value] != person.attributes[:vital_signs][key][:value]
        # puts "Found difference between person and clone: #{key} => #{vital[:value]} != #{clone.attributes[:vital_signs][key][:value]}"
        found_diff = true
        break
      end
    end
    assert(found_diff)

    # Look for differences in the generic module history
    clone.attributes[:generic].each do |key, state|
      clone_states = state.history.map(&:name)
      person_states = person.attributes[:generic][key].history.map(&:name) rescue []
      assert(clone_states.length >= person_states.length)
    end
  end

end
