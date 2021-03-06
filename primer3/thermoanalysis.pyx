# Copyright (C) 2014. Ben Pruitt & Nick Conway; Wyss Institute
# See LICENSE for full GPLv2 license.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
'''
primer3.thermoanalysis
~~~~~~~~~~~~~~~~~~~~~~

Contains Cython functions and classes that enable repeated thermodynamic
calculations using common calculation parameters.


Calculations are performed under the following paradigm:

1) Instantiate ThermoAnalysis object with appropriate parameters

    oligo_calc = ThermoAnalysis(mv_conc=50, dv_conc=0.2)

2) Use the object instance for subsequent calculations

    for primer in primer_list:
        print(oligo_calc.calcTm(primer))  # Print the melting temp

3) (optional) You can update an individual parameter at any time
    
    oligo_calc.mv_conc = 80  # Increaase the monovalent ion conc to 80 mM


'''

from cpython.version cimport PY_MAJOR_VERSION
import atexit

# ~~~~~~~~~~~~~~~~~~~~~~~~~ External C declarations ~~~~~~~~~~~~~~~~~~~~~~~~~ #

cdef extern from "oligotm.h":
    ctypedef enum tm_method_type:
        breslauer_auto      = 0
        santalucia_auto     = 1

    ctypedef enum salt_correction_type:
        schildkraut    = 0
        santalucia     = 1
        owczarzy       = 2

    double seqtm(const char*,
                     double,
                     double,
                     double,
                     double,
                     int,
                     tm_method_type,
                     salt_correction_type,
                     )


# ~~~~~~~~~~~~~~~ Utility functions to enforce UTF-8 encoding ~~~~~~~~~~~~~~~ #

cdef unsigned char[:] _chars(s):
    cdef unsigned char[:] o
    if isinstance(s, str):
        # encode to the specific encoding used inside of the module
        o = memoryview(bytearray((<str>s).encode('utf8')))
        return o
    return memoryview(s)

cdef inline bytes _bytes(s):
    IF IS_PY_THREE == 1:
        if isinstance(s, str):
            # encode to the specific encoding used inside of the module
            return (<str>s).encode('utf8')
        else:
            return s
    ELSE:
        return s

# ~~~~~~~~~ Load base thermodynamic parameters into memory from file ~~~~~~~~ #

def _loadThermoParams():
    cdef char*           param_path
    cdef thal_results    thalres
    import os
    PRIMER3_HOME = os.environ.get('PRIMER3HOME')
    ppath = os.path.join(PRIMER3_HOME, 'primer3_config/')
    ppathb = ppath.encode('utf-8')
    param_path = ppathb
    if get_thermodynamic_values(param_path, &thalres) != 0:
        raise IOError("Could not load thermodynamic config file %s" % ppath)

_loadThermoParams()

def _cleanup():
    destroy_thal_structures()

atexit.register(_cleanup)

# ~~~~~~~~~~~~~~ Thermodynamic calculations class declarations ~~~~~~~~~~~~~~ #

cdef class ThermoResult:
    ''' Class that wraps the ``thal_results`` struct from libprimer3 
    to expose tm, dg, dh, and ds values that result from a ``calcHairpin``,
    ``calcHomodimer``, ``calcHeterodimer``, or ``calcEndStability``
    calculation.
    '''

    def __cinit__(self):
        self.thalres.no_structure = 0;
        self.thalres.ds = self.thalres.dh = self.thalres.dg = 0.0
        self.thalres.align_end_1 = self.thalres.align_end_2 = 0

    property structure_found:
        ''' Whether or not a structure (hairpin, dimer, etc) was found as a 
        result of the calculation.
        '''
        def __get__(self):
            return not bool(self.thalres.no_structure)

    property tm:
        ''' Melting temperature of the structure in deg. C '''
        def __get__(self):
            return self.thalres.temp

    property ds:
        ''' deltaS (enthalpy) of the structure (cal/K*mol) '''
        def __get__(self):
            return self.thalres.ds

    property dh:
        ''' deltaH (entropy) of the structure (cal/mol) '''
        def __get__(self):
            return self.thalres.dh

    property dg:
        ''' deltaG (Gibbs free energy) of the structure (cal/mol) '''
        def __get__(self):
            return self.thalres.dg

    def checkExc(self):
        ''' Check the ``.msg`` attribute of the internal thalres struct and 
        raise a ``RuntimeError`` exception if it is not an empty string.
        Otherwise, return a reference to the current object.
        '''
        if len(self.thalres.msg):
            raise RuntimeError(self.thalres.msg)
        else:
            return self

    def __repr__(self):
        ''' Human-readable representation of the object '''
        return 'ThermoResult(structure_found={}, tm={:0.2f}, dg={:0.2f}, ' \
               'dh={:0.2f}, ds={:0.2f})'.format(self.structure_found,
                    self.tm, self.dg, self.dh, self.ds)

    def __str__(self):
        ''' Wraps ``__repr`` '''
        return self.__repr__()


cdef class ThermoAnalysis:
    ''' Python class that serves as the entry point for thermodynamic 
    calculations. Should be instantiated with the proper thermodynamic 
    parameters for seqsequence calculations (salt concentrations, correction
    methods, limits, etc.). See module docstring for more information.
    '''

    TM_METHODS = {
        'breslauer': 0,
        'santalucia': 1        
    }

    SALT_CORRECTION_METHODS = {
        'schildkraut': 0,
        'santalucia': 1,
        'owczarzy': 2            
    }

    def __cinit__(self, 
                  thal_type=1,
                  mv_conc=50,
                  dv_conc=1.5,
                  dntp_conc=0.2,
                  dna_conc=200,
                  temp_c=37,
                  max_loop=30,
                  temp_only=0,
                  debug=0,
                  max_nn_length=60,
                  tm_method=1,
                  salt_correction_method=1):
        self.thalargs.type = thal_type

        self.thalargs.mv = mv_conc;
        self.thalargs.dv = dv_conc;
        self.thalargs.dntp = dntp_conc;
        self.thalargs.dna_conc = dna_conc;
        self.thalargs.temp = temp_c + 273.15;
        self.thalargs.maxLoop = max_loop;
        self.thalargs.temponly = temp_only;
        self.thalargs.debug = debug;

        self.max_nn_length = max_nn_length;

        self.tm_method = tm_method
        self.salt_correction_method = salt_correction_method

    # ~~~~~~~~~~~~~~~~~~~~~~ Property getters / setters ~~~~~~~~~~~~~~~~~~~~~ #

    property thal_type:
        ''' The type of thermodynamic calculation '''
        def __get__(self):
            return self.thalargs.type

    property mv_conc:
        ''' Concentration of monovalent cations (mM) '''
        def __get__(self):
            return self.thalargs.mv
        def __set__(self, value):
            self.thalargs.mv = value

    property dv_conc:
        ''' Concentration of divalent cations (mM) '''
        def __get__(self):
            return self.thalargs.dv
        def __set__(self, value):
            self.thalargs.dv = value

    property dntp_conc:
        ''' Concentration of dNTPs (mM) '''
        def __get__(self):
            return self.thalargs.dntp
        def __set__(self, value):
            self.thalargs.dntp = value

    property dna_conc:
        ''' Concentration of DNA oligos (nM) '''
        def __get__(self):
            return self.thalargs.dna_conc
        def __set__(self, value):
            self.thalargs.dna_conc = value

    property temp:
        ''' Simulation temperature (deg. C) '''
        def __get__(self):
            return self.thalargs.temp - 273.15
        def __set__(self, value):
            self.thalargs.temp = value + 273.15

    property max_loop:
        ''' Maximum hairpin loop size (bp) '''
        def __get__(self):
            return self.thalargs.maxLoop

        def __set__(self, value):
            self.thalargs.maxLoop = value

    property tm_method:
        ''' Method used to calculate melting temperatures. May be provided as 
        a string (see TM_METHODS) or the respective integer representation.
        '''
        def __get__(self):
            return self._tm_method

        def __set__(self, value):
            if isinstance(value, (int, long)):
                self._tm_method = value
            else:
                int_value = ThermoAnalysis.TM_METHODS.get(value)
                if int_value is not None:
                    self._tm_method = int_value
                else:
                    raise ValueError('{} is not a valid `tm_method` type'
                                     ''.format(value))

    property salt_correction_method:
        ''' Method used for salt corrections applied to melting temperature 
        calculations. May be provided as a string (see SALT_CORRECTION_METHODS) 
        or the respective integer representation.
        '''
        def __get__(self):
            return self._salt_correction_method

        def __set__(self, value):
            if isinstance(value, (int, long)):
                self._salt_correction_method = value
            else:
                int_value = ThermoAnalysis.SALT_CORRECTION_METHODS.get(value)
                if int_value is not None:
                    self._salt_correction_method = int_value
                else:
                    raise ValueError('{} is not a valid '
                                     '`salt_correction_method` type'
                                     ''.format(value))

    # ~~~~~~~~~~~~~~ Thermodynamic calculation instance methods ~~~~~~~~~~~~~ #

    cdef inline ThermoResult calcHeterodimer_c(ThermoAnalysis self,
                                               unsigned char *s1,
                                               unsigned char *s2):
        cdef ThermoResult tr_obj = ThermoResult()

        self.thalargs.dimer = 1 
        self.thalargs.type = <thal_alignment_type> 1
        thal(<const unsigned char*> s1, <const unsigned char*> s2,
         <const thal_args *> &(self.thalargs), &(tr_obj.thalres), 0)
        return tr_obj

    def calcHeterodimer(ThermoAnalysis self, seq1, seq2):
        ''' Calculate the heterodimer formation thermodynamics of two DNA 
        sequences, ``seq1`` and ``seq2``
        '''
        # first convert any unicode to a byte string and then
        # cooerce to a unsigned char *
        # see http://docs.cython.org/src/tutorial/strings.html#encoding-text-to-bytes
        py_s1 = <bytes> _bytes(seq1)
        cdef unsigned char* s1 = py_s1
        py_s2 = <bytes> _bytes(seq2)
        cdef unsigned char* s2 = py_s2
        return ThermoAnalysis.calcHeterodimer_c(<ThermoAnalysis> self, s1, s2)

    cdef inline ThermoResult calcHomodimer_c(ThermoAnalysis self, 
                                             unsigned char *s1):
        cdef ThermoResult tr_obj = ThermoResult()

        self.thalargs.dimer = 1 
        self.thalargs.type = <thal_alignment_type> 1
        thal(<const unsigned char*> s1, <const unsigned char*> s1,
         <const thal_args *> &(self.thalargs), &(tr_obj.thalres), 0)
        return tr_obj

    def calcHomodimer(ThermoAnalysis self, seq1):
        ''' Calculate the homodimer formation thermodynamics of a DNA 
        sequence, ``seq1``
        '''
        # first convert any unicode to a byte string and then
        # cooerce to a unsigned char *
        py_s1 = <bytes> _bytes(seq1)
        cdef unsigned char* s1 = py_s1
        return ThermoAnalysis.calcHomodimer_c(<ThermoAnalysis> self, s1)

    cdef inline ThermoResult calcHairpin_c(ThermoAnalysis self, 
                                           unsigned char *s1):
        cdef ThermoResult tr_obj = ThermoResult()

        self.thalargs.dimer = 0
        self.thalargs.type = <thal_alignment_type> 4
        thal(<const unsigned char*> s1, <const unsigned char*> s1,
         <const thal_args *> &(self.thalargs), &(tr_obj.thalres), 0)
        return tr_obj

    def calcHairpin(ThermoAnalysis self, seq1):
        ''' Calculate the hairpin formation thermodynamics of a DNA 
        sequence, ``seq1``
        '''
        # first convert any unicode to a byte string and then
        # cooerce to a unsigned char *
        py_s1 = <bytes> _bytes(seq1)
        cdef unsigned char* s1 = py_s1
        return ThermoAnalysis.calcHairpin_c(<ThermoAnalysis> self, s1)

    cdef inline ThermoResult calcEndStability_c(ThermoAnalysis self,
                                               unsigned char *s1,
                                               unsigned char *s2):
        cdef ThermoResult tr_obj = ThermoResult()

        self.thalargs.dimer = 1 
        self.thalargs.type = <thal_alignment_type> 2
        thal(<const unsigned char*> s1, <const unsigned char*> s2,
         <const thal_args *> &(self.thalargs), &(tr_obj.thalres), 0)
        return tr_obj

    def calcEndStability(ThermoAnalysis self, seq1, seq2):
        ''' Calculate the 3' end stability of DNA sequence `seq1` against DNA 
        sequence `seq2`
        '''
        # first convert any unicode to a byte string and then
        # cooerce to a unsigned char *
        # see http://docs.cython.org/src/tutorial/strings.html#encoding-text-to-bytes
        py_s1 = <bytes> _bytes(seq1)
        cdef unsigned char* s1 = py_s1
        py_s2 = <bytes> _bytes(seq2)
        cdef unsigned char* s2 = py_s2
        return ThermoAnalysis.calcEndStability_c(<ThermoAnalysis> self, s1, s2)

    cdef inline double calcTm_c(ThermoAnalysis self, char *s1):
        cdef thal_args *ta = &self.thalargs
        return seqtm(<const char*> s1, 
                     ta.dna_conc, 
                     ta.mv, 
                     ta.dv,
                     ta.dntp, 
                     self.max_nn_length, 
                     <tm_method_type>
                     self.tm_method,
                     <salt_correction_type> self.salt_correction_method)

    def calcTm(ThermoAnalysis self, seq1):
        ''' Calculate the melting temperature (Tm) of a DNA sequence (deg. C).
        '''
        # first convert any unicode to a byte string and then
        # cooerce to a unsigned char *
        py_s1 = <bytes> _bytes(seq1)
        cdef char* s1 = py_s1
        return ThermoAnalysis.calcTm_c(<ThermoAnalysis> self, s1)
