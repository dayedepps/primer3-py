

import os
import random
import sys
import unittest

LOCAL_DIR = os.path.dirname(os.path.realpath(__file__))
PACKAGE_DIR = os.path.dirname(LOCAL_DIR)
sys.path = [PACKAGE_DIR] + sys.path

import primer3

# Insure that we imported the local copy of primer3-py
print primer3.__file__
assert primer3.__file__ == os.path.join(PACKAGE_DIR, 'primer3', '__init__.pyc')

class TestCalcHeterodimer(unittest.TestCase):

    def test_defined(self):  # known to fail
        oligo_a = 'AGCTATCC'
        oligo_b = 'GTATAGCA'
        # oligo_a = 'ACTTGACT' 
        # oligo_b = 'ACTTGCAC'

        # 'GTGCGGTT' 'CCAGACAG'
        self.assertEqual(
            primer3.calcHeterodimer(oligo_a, oligo_b).dg,
            primer3.calcHeterodimer(oligo_b, oligo_a).dg)

    def test_random(self):  # more extensive check
        failures = 0
        for _ in range(10000):
            oligo_a = ''.join([random.choice('ATGC') for _ in range(8)])
            oligo_b = ''.join([random.choice('ATGC') for _ in range(8)])
            failure = (
                primer3.calcHeterodimer(oligo_a, oligo_b).dg !=
                primer3.calcHeterodimer(oligo_b, oligo_a).dg)
            if failure:
                print(oligo_a, oligo_b)
            failures += int(failure)
        if failures > 0:
            self.assertTrue(False, 
                '%d out of 10000 random tests failed' % failures)


if __name__ == '__main__':
    unittest.main(verbosity=2)