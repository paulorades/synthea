require_relative '../test_helper'

class MetricsTest < Minitest::Test
  def setup
  end

  def test_duration
    assert_equal "2.0 years (About 2 years and 0 months)", Synthea::Tasks::Metrics.duration(2.years)
    assert_equal "2.01 years (About 2 years and 0 months)", Synthea::Tasks::Metrics.duration(2.years + 3.days)
    assert_equal "1.07 years (About 1 years and 1 months)", Synthea::Tasks::Metrics.duration(10.months + 3.months)

    # 1 month is defined to be 30 days
    assert_equal "6.0 months (About 6 months and 0 days)", Synthea::Tasks::Metrics.duration(6.months)
    assert_equal "6.1 months (About 6 months and 3 days)", Synthea::Tasks::Metrics.duration(6.months + 3.days)
    assert_equal "7.13 months (About 7 months and 4 days)", Synthea::Tasks::Metrics.duration(6.months + 34.days)
    assert_equal "1.4 months (About 1 months and 12 days)", Synthea::Tasks::Metrics.duration(6.weeks)

    # week
    assert_equal "3.0 weeks (About 3 weeks and 0 days)", Synthea::Tasks::Metrics.duration(3.weeks)
    assert_equal "1.43 weeks (About 1 weeks and 3 days)", Synthea::Tasks::Metrics.duration(1.weeks + 3.days)

    # days
    assert_equal "2.0 days (About 2 days and 0 hours)", Synthea::Tasks::Metrics.duration(2.days)
    assert_equal "2.0 days (About 2 days and 0 hours)", Synthea::Tasks::Metrics.duration(2 * 24 * 60 * 60)
    assert_equal "2.5 days (About 2 days and 12 hours)", Synthea::Tasks::Metrics.duration(2.days + 12.hours)

    # hours
    assert_equal "2.0 hours (About 2 hours and 0 mins)", Synthea::Tasks::Metrics.duration(2.hours)
    assert_equal "9.5 hours (About 9 hours and 30 mins)", Synthea::Tasks::Metrics.duration(9.hours + 30.minutes)

    # minutes
    assert_equal "2.0 minutes (About 2 minutes and 0 seconds)", Synthea::Tasks::Metrics.duration(2.minutes)
    assert_equal "2.0 minutes (About 2 minutes and 0 seconds)", Synthea::Tasks::Metrics.duration(120.seconds)


    # seconds
    assert_equal "2 seconds", Synthea::Tasks::Metrics.duration(2.seconds)
    assert_equal "10 seconds", Synthea::Tasks::Metrics.duration(10)

    assert_equal "0", Synthea::Tasks::Metrics.duration(0)
    assert_equal "0", Synthea::Tasks::Metrics.duration(0.years)
    assert_equal "0", Synthea::Tasks::Metrics.duration(0.days)

  end
end