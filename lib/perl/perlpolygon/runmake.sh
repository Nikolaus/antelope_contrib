: # use perl
eval 'exec perl -S $0 "$@"'
if 0;

if ( @ARGV > 1 )
    { die ( "Usage: $0 [all|install|clean]\n" ) ; }

delete $ENV{'KEEP_STATE'} ; 

if ( $ARGV[0] eq "clean" ) { 
    system ( "make -f Makefile @ARGV" ) ; 
} elsif ( $ARGV[0] eq "install" ) { 
    system ( "make -f Makefile ; make -f Makefile install " ) ;
} elsif ( $ARGV[0] eq "all" ) { 
    system ( "make -f Makefile " ) ;
} else { 
    system ( "make -f Makefile " ) ;
}

# $Id$ 
