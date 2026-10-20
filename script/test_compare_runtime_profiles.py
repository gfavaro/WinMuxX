import unittest
from script.compare_runtime_profiles import compare, validate_environments


def sample(cpu=.1, wakeups=60, growth=0):
    return dict(status='completed', elapsed_seconds=120, cpu_percent_one_core=cpu,
                pkg_idle_wkups=wakeups, footprint_first_decile_median_mib=100,
                footprint_last_decile_median_mib=100 + growth)


class ProfileComparisonTest(unittest.TestCase):
    def testNoiseAndThresholds(self):
        self.assertEqual(compare(sample(), [sample(cpu=.5, growth=4)])['status'], 'passed')
        self.assertEqual(compare(sample(), [sample(cpu=2)])['status'], 'repeat_required')
        self.assertEqual(compare(sample(), [sample(cpu=2)] * 3)['status'], 'confirmed_regression')

    def testUsesMedianRatherThanOneSpike(self):
        self.assertEqual(compare(sample(), [sample(), sample(), sample(cpu=30)])['status'], 'passed')

    def testMemoryAndWakeups(self):
        result = compare(sample(), [sample(wakeups=240, growth=10)] * 3)
        self.assertEqual(set(result['flags']), {'wakeups', 'growth'})

    def testIncompleteDataCannotPass(self):
        invalid = sample()
        invalid['status'] = 'interrupted'
        with self.assertRaises(ValueError): compare(sample(), [invalid])

    def testEnvironmentMismatchCannotPass(self):
        environment = dict(os='macOS', monitors=[{'name': 'display'}], config_sha256='hash')
        validate_environments(environment, dict(environment))
        with self.assertRaisesRegex(ValueError, 'monitors'):
            validate_environments(environment, dict(environment, monitors=[]))
        with self.assertRaisesRegex(ValueError, 'Missing'):
            validate_environments({}, environment)
