import _orb

from _orb import *

class Orb():
    """Create an Antelope Orb connection
        
        Orb(orbname)
        Orb(orbname, perm)
        Orb(orbname=address)
        Orb(orbname=address, perm='r')
    """
    
    def __init__(self, *args, **kwargs):

        self._orbname = None
        self._orbfd = -1
        self._perm = 'r'
    
        if(kwargs.has_key('orbname')):

            self._orbname = kwargs['orbname']

        if(kwargs.has_key('perm')):

            self._perm = kwargs['perm']

        if(len(args) >= 1):

            if(isinstance(args[0], str)):

                self._orbname = args[0]

            else:

                raise TypeError, 'Orb constructor arguments not understood'

        if(len(args) >= 2):

            if(isinstance(args[1], str)):

                self._perm = args[1]

            else:

                raise TypeError, 'Orb constructor arguments not understood'
        
        if(self._orbname and not isinstance(self._orbname, str)):
            
            raise TypeError, 'dbname must be a string'

        if(not isinstance(self._perm, str)):
            
            raise TypeError, 'perm must be a string'

        if(self._orbname):

            self._orbfd = _orb._orbopen(self._orbname, self._perm)

	    if(self._orbfd < 0):

	        raise RuntimeError, 'Failure opening orbserver %s' % self._orbname

    def __str__(self):
        
        return ("\n[Orb:\n" +
            "\torbfd = %d\n" % self._orbfd +
            "\torbname  = %d\n" % self._orbname +
            "]\n")

    def close(self):
        """Close an Antelope orb connection"""

        _orb._orbclose(self._orbfd)

    def ping(self):
        """Query orbserver version"""

        return _orb._orbping(self._orbfd)

    def tell(self):
        """Query orb read-head position"""

        return _orb._orbtell(self._orbfd)


def orbopen(orbname, perm = 'r'):
    """Open an Antelope orb connection"""

    return Orb(orbname, perm)


def orbclose(orb):
    """Close an Antelope orb connection"""

    orb.close()

    return 


def orbping(orb):
    """Query orbserver version"""

    return orb.ping()


def orbtell(orb):
    """Query current connection read-head position"""

    return orb.tell()


if __name__ == '__main__':
    import unittest
    import os
    orbname = ':dq'

    class Testorb_fixture():

        def start(self):

            os.chdir("/tmp")
            os.system("pfcp orbserver .")
            os.system("orbserver -p " + orbname + " orbserver &")
            os.system("sleep 3")

        def stop(self):

            os.system("echo halt | orbstat -i " + orbname)

    class Testorb(unittest.TestCase):

        def test_Orb_constructor(self):

	    orb = Orb(orbname)

	    self.assertRaises(RuntimeError, Orb, 'not an orb')
	    
        def test_procedure_orbopen(self):

	    orb = orbopen(orbname, 'r')

        def test_procedure_orbclose(self):

	    orb = orbopen(orbname, 'r')

	    orbclose(orb)

        def test_procedure_orbping(self):

	    orb = orbopen(orbname, 'r')

            version = orbping(orb)

	    self.assertTrue(version > 0)

	    orbclose(orb)

        def test_procedure_orbtell(self):

	    orb = orbopen(orbname, 'r')

            pktid = orbtell(orb)

	    self.assertTrue(pktid > 0)

	    orbclose(orb)

    server = Testorb_fixture()
    server.start()
    suite = unittest.makeSuite(Testorb)
    runner = unittest.TextTestRunner()
    runner.run(suite)
    server.stop()