"""Old settings must never recreate removed software audio filters."""
import json
import unittest
from barracuda_pair import audio


class RemovedGraphTests(unittest.TestCase):
    def test_legacy_enabled_flags_cannot_create_software_filters(self):
        state = audio.defaults()
        for item in state['equalizers'].values():
            item['enabled'] = True
        state['sidetone']['enabled'] = True
        documents = audio.documents(state, [])
        for value in documents.values():
            self.assertNotIn('filter-chain', json.dumps(value))
            self.assertNotIn('filter.smart', json.dumps(value))
