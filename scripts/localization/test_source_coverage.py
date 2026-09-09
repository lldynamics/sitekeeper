import unittest
from check_source_coverage import placeholders, requested_keys, resource_values


class SourceCoverageTests(unittest.TestCase):
    def test_comments_do_not_create_requirements(self):
        source = '''// String(localized: "ignored")
/* outer /* String(localized: "nested") */ end */
let value = String(localized: "https://example.test/key")
'''
        self.assertEqual(list(requested_keys(source)), [('https://example.test/key', 3)])

    def test_escaped_keys_and_interpolation(self):
        source = r'''String(localized: "line\n\"quoted\"")
String(localized: "dynamic \(name)")'''
        self.assertEqual(list(requested_keys(source)), [('line\n"quoted"', 1)])

    def test_missing_on_both_sides_is_still_a_source_requirement(self):
        self.assertEqual(set(key for key, _ in requested_keys('String(localized: "New action")')), {'New action'})
        self.assertNotIn('New action', resource_values('"Old action" = "Old action";'))

    def test_duplicate_resources_fail(self):
        with self.assertRaises(ValueError):
            resource_values('"key"="value"; "key"="other";')

    def test_placeholder_reordering_and_width(self):
        self.assertEqual(placeholders('%@ %lld %.2f %%'), placeholders('%3$.2f %2$lld %1$@ %%'))
        self.assertNotEqual(placeholders('%lld'), placeholders('%@'))

    def test_unindexed_reordering_and_star_arguments_are_checked(self):
        self.assertNotEqual(placeholders('%@ %lld'), placeholders('%lld %@'))
        self.assertEqual(placeholders('%*.*f'), placeholders('%d %d %f'))
        self.assertNotEqual(placeholders('%*.*f'), placeholders('%f'))


if __name__ == '__main__':
    unittest.main()
