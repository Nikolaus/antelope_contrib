
use Datascope;
use orb ;

use Getopt::Std;

# mk_dbops - generate/update adoption, deployment, dlsite, comm tables 
#		after installation, removal, adoption or update
#
#
# Add X to Adoption types, triggering write to new db for a CEUSN-type adoption/transition 
#  - J.Eakins 9/17/2013 
#
#
# J.Eakins
# 1/2009
# jeakin@ucsd.edu
#


  my $pgm = $0 ;
  $pgm =~ s".*/"" ;
  elog_init ( $pgm, @ARGV) ;
  my $cmd = "\n$0 @ARGV" ;

  elog_notify($cmd);

  if ( !getopts('knvyIRUAm:w:W:s:S:p:P:C:V:') || @ARGV < 4 || @ARGV > 6 ) {
    die ("USAGE: $0 { -I | -U | -R | -A }  [-k] [-n] [-v] [-V vnet] [-p pf] [-m match_pkts] [-P prelimORB] [-S statusORB] [-C cmdORB] [-w prelimwfDB] [-W wfDB] [-s siteDB] dbopsdb snet sta timestamp [comm_provider [comm_type] ]  \n");
  }

  $dbops	= $ARGV[0];
  $snet  	= $ARGV[1];
  $sta   	= $ARGV[2];
# time of record change for update, certtime for install, decert time for rm, time for adoption
  $mytime	= $ARGV[3];		
  $newprovider	= $ARGV[4];
  $newcommtype	= $ARGV[5];

  if (is_epoch_string($mytime)<1) {
	elog_die("Problem with input time: $mytime.  Make sure you use a valid time string.\n");
  } else {
	$mytime = str2epoch($mytime);
  }
 

  if (!$newprovider && ($opt_I || $opt_U) ) {
	elog_complain("\nMust specify a comms provider for installs and updates along with a time.\n"); 
	elog_complain("For an update, the time is the time of an update. \n") if $opt_U; 
	elog_complain("For a new install, the time is the certification time. \n") if $opt_I; 
	elog_complain("You can specify 'no comms' for commtype and 'none' for provider if comms are not installed.\n"); 
        &usage ;
  } 

  if (!$newcommtype) {
     if ( $opt_I )  {
	elog_complain("Must specify a comm type for installs.\n"); 
	&usage;
     } elsif($opt_U) {
	elog_notify("No new comm type specified.  Will use pre-existing commtype if possible.\n"); 
	$samecomm = 1;
        if (!$newprovider) {
	   elog_complain("No new provider specified!  Using same comm type is ok with an update, but no new record can be added for same provider.\n"); 
	   &usage ;
	}
     }
  }

# set up some defaults

$dmctime	= 19880899199.00000;		# DMC requested time translates to 12/31/2599 23:59:59 

$pdcc	=	"-";
$sdcc	=	"-";
$dlname = 	"$snet" . "_" . "$sta" ;

$startnull	= "-9999999999.99900";
$endnull	= "9999999999.99900";
$stasub 	= "sta=='$sta'";
$dlstasub 	= "dlname=='$dlname'";
$nullsub 	= "endtime=='9999999999.99900'";

$commsub	= "$stasub && $nullsub";
$dlsitesub	= "$dlstasub && $nullsub";
$depsub		= "$stasub" ;

# read pf file to get default orbs and wf dbs

  if ($opt_p) {
     $Pf = $opt_p ;
  } else {
     $Pf = mk_dbops ;  
  }

  $status_orb	= pfget($Pf, 'status_orb');
  $cmd_orb	= pfget($Pf, 'cmd_orb');
  $prelim_orb	= pfget($Pf, 'prelim_orb');
  $wfdb 	= pfget($Pf, 'wfdb');
  $vnet  	= pfget($Pf, 'vnet');
  $pdcc  	= pfget($Pf, 'pdcc');
  $status_orb	= pfget($Pf, 'status_orb');
  $packet_ext	= pfget($Pf, 'packet_match') ;  
  $chansub	= pfget($Pf, 'channel_match')  ;
  $chansub	= "chan=~/$chansub/" ;

  $status_orb	= pfget($Pf, 'status_orb');

  $ref		= pfget($Pf, 'adoption_types' ) ;
  %adoption_types = %$ref; 

  $stagesub	= "sta=='$sta'&&$chansub&&gtype=~/sensor|seismometer/&&endtime!='9999999999.99900'" ;
  $wfsub 	= "$stasub && $chansub";

# command line overrides 
  $status_orb	= $opt_S if ($opt_S) ;
  $cmd_orb	= $opt_C if ($opt_C) ;
  $prelim_orb	= $opt_P if ($opt_P) ;
  $wfdb		= $opt_W if ($opt_W) ; 
  $prelimwf_db	= $opt_w if ($opt_w) ;
  $vnet 	= $opt_V if ($opt_V) ;

  $vnetsub	= "vnet=='$vnet'" ;

if ($opt_s) {
  $sitedb		= $opt_s ;
} else {
  $sitedb		= $dbops ;
}

@ops		= dbopen ( $dbops, "r+") ; 
@stage 		= dbopen_table ( $sitedb.".stage", "r") ; 
# only opt_A and non-EARN
@wfdisc		= dbopen_table ($wfdb.".wfdisc", "r") if ($opt_R || $opt_W || !$newvnet) ; 

elog_notify(0,"\t dbops  database: $dbops\n");
elog_notify(0,"\t dbsite database: $sitedb\n") if $opt_s ;
elog_notify(0,"\t wf     database: $wfdb\n") if ($opt_R || $opt_W);

@deployment	= dblookup(@ops,  "", "deployment" , "" , "");
@dlsite		= dblookup(@ops,  "", "dlsite" ,     "" , "");
@comm		= dblookup(@ops,  "", "comm" ,       "" , "");
@adoption	= dblookup(@ops,  "", "adoption" ,     "" , "");



  if ($opt_I) {
    $type = "INSTALL" ;
    if ($opt_R || $opt_U || $opt_A ) {
	elog_die("Must use only one of -A, -I, -R, -U \n");
    } 
  } elsif ($opt_R) {
    $type = "REMOVAL" ;
    if ($opt_I || $opt_U || $opt_A ) {
	elog_die("Must use only one of -A, -I, -R, -U \n");
    } 

  } elsif ($opt_A) {
    $type = "ADOPTION" ;
    if ($opt_I || $opt_U || $opt_R ) {
	elog_die("Must use only one of -A, -I, -R, or -U \n");
    } 

# hard code allowed adoption_codes for now ... 

#    # setup default for adoption types 
#    foreach $key (keys %adoption_types) {
#	$adopt_code = $key ;
#	$adopt_phr  = $adoption_types{$adopt_code};
#    }


    $atype	= ask( "Adoption type (E|T|R|X|-):  " ) ;


    &new_sta_net_dcc ;		# get new sta, net, and dcc

    if( $atype=~ /^\s*$/ ) {
        $atype= "-";
	$adopt_phrase  = "-" ;
    } elsif ( $atype=~/E|R|X/ ) {	# EARN/REFNET/CEUSN-1N4 stations get new vnet code; TRANSITIONS, do not
	$newvnet = ask ( "New vnet code for  $adoption_types{$atype}  station (_XX-XXXXXXXX):  ") ;  
        if( $newvnet=~ /^\s*$/ ) {
          $newvnet= "-";
        }

	$type = $type . "   -  $adoption_types{$atype} ";

	$earntime = ask ( "Time of $adoption_types{$atype} transition ('now'):  ") ;
        if( $earntime=~ /^\s*$/ ) {
          $earntime = now() ;
        } else {
	  $earntime = str2epoch($earntime) ; 
 	}

	$adopt_phrase  = $adoption_types{$atype};

	if ( $atype=~/X/) {	# CEUSN style transition - new deployment table needed
	   $newdb= ask ( "New database for deployment and comms (new/db):  ") ;  
	   if ( $newdb=~ /^\s*$/ ) {
		$newdb = "new/db";
	   }

	   # need to check to see if new/db exists (both preceding path and the db) 
	   #  and check to see if deployment/comm are writable	   
	   ($newdbpath, $newdb, $newsuffix) = parsepath ($newdb); 
	   elog_die("Do not include the table name when choosing a db:  $newdbpath/$newdb.$newsuffix")  if $newsuffix; 
	   unless(-d $newdbpath){
	       mkdir $newdbpath or die "Couldn't create dir: [$newdbpath] ($!)";
	   }

           eval { @db  = dbopen_table("$newdbpath/$newdb.deployment","r+") or elog_complain("Can't open table: $newdbpath/$newdb.deployment") };

	   $newdb = "$newdbpath/$newdb" ;

           @newops            = dbopen ( $newdb, "r+") ;
	   @newdeployment     = dblookup(@newops,  "", "deployment" , "" , "");
	   @newdlsite         = dblookup(@newops,  "", "dlsite" ,     "" , "");
	   @newcomm           = dblookup(@newops,  "", "comm" ,       "" , "");

	}

    } elsif ( $atype == 'T' ) {	# Transition to regional network 
	$type = $type . "   -  TRANSITION ";
	$adopt_phrase  = $adoption_types{$atype};

    } else {
	$type = $type . "   -  OTHER ";
	$atype = "other" ;
	$adopt_phrase = "other" ;
    }

  } elsif ($opt_U) {
    $type = "UPDATE" ;
#    $newcommtime = $opt_U ;
    if ($opt_R || $opt_I ) {
	elog_die("Must use only one of -A, -I, -R, -U \n");
    } 

  } else {
    elog_die("Must specify either -I, -R, or -U, -A.  Corresponds to install, removal, update, or adoption \n");
  }

  elog_notify("\n  ---  Dbops update type:   $type  --- \n\n");

# check for "alive" prelim orb if you are removing or installing.   
#  not needed if you are using prelimwf_db

if ($opt_I && !$opt_w ) {		
  $preorb    = orbopen   ($prelim_orb, "r&" );
  elog_notify("Prelim orb:  $prelim_orb\n") if $opt_v ;
 
  if ($preorb == -1) {
     elog_die("Can't open $prelim_orb\n") ;
  }
}

# check for "alive" status and cmd orb if you are updating or installing.   
#  not needed if you are using prelimwf_db

if ($opt_U || $opt_I) {
  $statorb    = orbopen   ($status_orb, "r&" );
  elog_notify("Status orb:  $status_orb\n") if $opt_v ;
 
  if ($statorb == -1) {
     elog_die("Can't open $status_orb\n") ;
  }
  if (!$opt_n) {
    $cmdorb    = orbopen   ($cmd_orb, "r&" );
    elog_notify("Cmd orb:  $cmd_orb\n") if $opt_v ;
 
    if ($cmdorb == -1) {
     elog_die("Can't open $cmd_orb\n") ;
    }
  }
}

if ($opt_U) {

  elog_notify("Starting UPDATE specific commands\n") if $opt_v ;

  elog_notify("Command line timestamp:  ". &strydtime($mytime) . " used for comm.endtime, new comm.time, dlsite.endtime, and new dlsite.endtime\n");

  elog_notify("Creating backup of tables:  \n") if ($opt_v) ;

  foreach $table ("comm", "dlsite") {
        elog_notify("\t  $table  \n") if ($opt_v) ;
	$table_filename =  dbquery(@$table, "dbTABLE_FILENAME") ; 
	$cmd  = "/bin/cp $table_filename $table_filename+" ;
	if (-e $table_filename) {
	  &run("$cmd");
	  push(@rm_list,$table_filename) ;
	} else {
	  elog_notify("$table_filename does not exist - no backup made\n");
	}
  }

  elog_notify("Backup tables will be removed upon success.\n") if ($opt_v && !$opt_k) ;


# modify old record and update new in comm table
  &modifycomm($dbops,$mytime-1) ;

  $newcommtype = (defined $samecomm)  ? $commtype: $newcommtype ;

  &add2comm($dbops,$sta,$mytime,$newcommtype,$newprovider) ;

  &modifydlsite($dbops) ;

} elsif ($opt_A) {

  elog_notify("Starting ADOPTION specific commands\n");

  if ($newvnet) {	# this means its an EARN or TRANSITION, or CEUSN/1N4 

#   for EARN, endtime is timestamp from ask:  earntime
#   for EARN/TRNSITION, equip_removal is null
#   for EARN, deployment.decert uses time from command line
#   for CEUSN/1N4, use same values as EARN, but need to copy comm info to new dbops tables, and generate new deployment info

    elog_notify("Command line timestamp:  ". &strydtime($mytime) . " used for deployment.decert_time and new deployment.cert_time\n");

    elog_notify("Creating backup of tables:  \n") if ($opt_v) ;

    foreach $table ("adoption", "deployment") {
        elog_notify("\t  $table  \n") if ($opt_v) ;
	$table_filename =  dbquery(@$table, "dbTABLE_FILENAME") ; 
	$cmd  = "/bin/cp $table_filename $table_filename+" ;
	if (-e $table_filename) {
	  &run("$cmd");
	  push(@rm_list,$table_filename) ;
	} else {
	  elog_notify("$table_filename does not exist - no backup made\n");
	}
    }

    elog_notify("\t starting close_deployment on $dbops\n");

    &close_deployment ($dbops, $earntime, $endnull, $mytime ) ; 
  
    $stime = &get_stagestarttime ;

    elog_notify("newvnet is: $newvnet\n") if ($opt_v);
    elog_notify("newnet  is: $newnet \n") if ($opt_v);

    if ($atype =~/X/) {
#  add to the new deployment table
      elog_notify("\t starting add2deployment for new deployment table, $newdb \n");
  

      elog_notify("Vnet: $newvnet; Snet: $newnet; Sta: $newsta; \n")  ;
      &add2deployment ($newdb, $newvnet, $newnet, $newsta, $earntime+0.001, $stime, $mytime) ; 

# need to pull commtype and provider from old comm table
      @single_comm = dbsubset (@comm, $commsub) ;           # get single open record from old comm table
      elog_die("No records in comm table matching $sta with null endtime\n") if (!dbquery(@single_comm, "dbRECORD_COUNT") ) ; 
      elog_die("Too many records in comm matching $sta\n") if (dbquery(@single_comm, "dbRECORD_COUNT") > 1) ; 
      $single_comm[3] = 0 ; 
      ($commtype,$provider) = dbgetv(@single_comm, qw(commtype provider) );

    #  add to the new comm table
      elog_notify("\t starting add2comm for new comm table\n");
      &add2comm($newdb,$newsta,$earntime+0.001,$commtype,$provider) ;
    # close out old deployment, comm, and dlsite records
      elog_notify("\t starting close_deployment for old deployment table\n");
      &close_deployment ($dbops, $earntime, $endnull, $mytime ) ; 
      &close_comm($dbops,$earntime); 

    # add to new dlsite

      if (!$opt_n) {
	elog_notify("Starting modification of dlsite via external program q330_location. \n")  ;
	elog_notify("This program assumes sitedb and dbops are the same..... \n")  ;
	&add2dlsite($newdb);
      } else {
	elog_notify("\n   You need to run q330_location to populate dlsite table\n\n") ;
      }

    } else {
      &add2deployment ($dbops, $newvnet, $newnet, $newsta, $earntime+0.001, $stime, $mytime) ; 
    }

    elog_notify("This is a $atype station.  No change to comm or dlsite.\n" ) if ($opt_v);

    &add2adoption($dbops,$earntime) ; 


  } else {	# adopted station, non-EARN (i.e. adoption/transition) 
		 #  What about transition to Reference network?  These may stay as TA and thus have no stage.endtime.

    elog_notify("Command line timestamp:  ". &strydtime($mytime) . " used for deployment.decert_time \n");

    elog_notify("Creating backup of tables:  \n") if ($opt_v) ;

    foreach $table ("adoption", "comm", "deployment", "dlsite") {
        elog_notify("\t  $table  \n") if ($opt_v) ;
	$table_filename =  dbquery(@$table, "dbTABLE_FILENAME") ; 
	$cmd  = "/bin/cp $table_filename $table_filename+" ;
	if (-e $table_filename) {
	  &run("$cmd");
	  push(@rm_list,$table_filename) ;
	} else {
	  elog_notify("$table_filename does not exist - no backup made\n");
	}
    } 

    $sendtime	= &get_stageendtime ;
    $wfendtime	= &get_wfendtime ;

    if ( $wfendtime > $sendtime ) {
	elog_die ("  ERROR!  Data exists after endtime for $sta specified in $sitedb.stage !!\n Fix input metadata!\n") ; 
    }

    &close_deployment($dbops, $wfendtime, $endnull, $mytime) ; 

    elog_notify("This is a $atype station.  Comm and dlsite will be changed.\n" )  if ($opt_v) ;

    &close_dlsite($dbops, $sendtime); 
    &close_comm($dbops, $sendtime) ;

    if ($adoption_type == 'T' ) {
	$atime = $sendtime ;
    } else {
	$atime = $mytime ;
    }

    &add2adoption($dbops,$atime) ; 
  }


} elsif ($opt_R) {

  elog_notify("Starting REMOVAL specific commands\n");
  elog_notify("Command line timestamp:  ". &strydtime($mytime) . " used for deployment.decert_time \n");

  foreach $table ("comm", "deployment", "dlsite") {
        elog_notify("\t  $table  \n") if ($opt_v) ;
	$table_filename =  dbquery(@$table, "dbTABLE_FILENAME") ; 
	$cmd  = "/bin/cp $table_filename $table_filename+" ;
	if (-e $table_filename) {
	  &run("$cmd");
	  push(@rm_list,$table_filename) ;
	} else {
	  elog_notify("$table_filename does not exist - no backup made\n");
	}
  }

  $sendtime = &get_stageendtime ;
  $wfendtime = &get_wfendtime ;

  if ( $wfendtime > $sendtime ) {
	elog_die ("  ERROR!  Data exists after endtime for $sta specified in $sitedb.stage !!\n Fix input metadata!\n") ; 
  }

# close_deployment used to be after close_dlsite, but if q330_location had been run 
#  when a removed station was not running, updates to deployment table would fail.
# Changed 3/31/2011 --J.Eakins

  &close_deployment($dbops, $wfendtime, $sendtime, $mytime) ; 
  &close_comm($dbops,$sendtime) ; # we want endtime to be $sendtime

  elog_notify("Closed comm record in database: $dbops\n")  if (opt_v) ;

# get dlsite.endtime from (last time in wfdisc?  stage.endtime? last data in orb?)
#   chose to use stage.endtime
#  NOTE:  if opt_A, -A, dlsite.endtime is set to NULL

  &close_dlsite($dbops, $sendtime) ; 

} elsif ($opt_I) {

  elog_notify("Starting INSTALL specific commands\n");

  elog_notify("Creating backup of tables:  \n") if ($opt_v) ;

  foreach $table ("comm", "deployment", "dlsite") {
        elog_notify("\t  $table  \n") if ($opt_v) ;
	$table_filename =  dbquery(@$table, "dbTABLE_FILENAME") ; 
	$cmd  = "/bin/cp $table_filename $table_filename+" ;
	if (-e $table_filename) {
	  &run("$cmd");
	  push(@rm_list,$table_filename) ;
	} else {
	  elog_notify("$table_filename does not exist - no backup made\n");
	}
  }

  elog_notify("Backup tables will be removed upon success.\n") if ($opt_v && !$opt_k) ;

#
#  elog_notify("Command line timestamp:  ". &strydtime($mytime) . " used for deployment.decert_time \n");
#

  $stime = &get_stagestarttime ;

  &add2comm($dbops,$sta,$stime,$newcommtype,$newprovider) ;

# get deployment.time from (first time in wfdisc?  stage.time?  first data in orb?)
#   chose to use first data in orb - override with -w

  if ($opt_w) {		# use time from input prelim wfdb
     @prewf 	= dbopen_table ( $prelimwf_db.".wfdisc", "r") ; 
     @prewf	= dbsubset (@prewf, $wfsub) ;

     elog_die("No records in prelim wfdisc matching station $sta and $chansub  \n") if (!dbquery(@prewf, "dbRECORD_COUNT") ) ; 

     @prewf 	= dbsort (@prewf, "time") ;	# get single record that will be updated

     $prewf[3] 	= 0 ;

     $dtime = dbgetv(@prewf, qw( time ) );
     dbfree(@prewf);

  } else {		# get time from prelim orb

     if ($opt_m) {
       $select = "$opt_m" ;	# Look for data packets
     } else {
       $select = $dlname . "(" . $packet_ext . ")" ;	# Look for data packets
     }

     $n = orbselect($preorb, $select) ;
     $n = orbposition($preorb, "oldest") ;

     if ($n < 1 ) {
        elog_die("Can't select $select packets from prelim orb, $prelim_orb\n");
     }

     ($pktid, $srcname, $pkttime, $packet, $nbytes) = orbreap($preorb) ;
     $dtime = $pkttime ;

  }

  &trim($dtime) ;

  &add2deployment($dbops, $vnet, $snet, $sta, $dtime, $stime, $mytime) ;  

  if (!$opt_n) {
     elog_notify("Starting modification of dlsite via external program q330_location. \n")  ;
     elog_notify("This program assumes sitedb and dbops are the same..... \n")  ;
     &add2dlsite($dbops);
  } else {
     elog_notify("\n   You need to run q330_location to populate dlsite table\n\n") ;
  }

}


dbclose (@ops);
dbfree (@stage) if ($opt_s) ;  
dbclose (@wfdisc) if ($opt_R || $opt_w) ;
dbclose (@newops) if ($opt_A) ; 

# cleanup backup tables unless -k
if (!$opt_k) {
   foreach $rm_tb (@rm_list) {
     $cmd = "/bin/rm $rm_tb+" ;
     &run("$cmd");
   }
}

elog_notify("\n - - - Finished $type modifications - - - \n\n");

exit ;


# SUBS below here

sub get_stageendtime {		# get the stage.endtime

  elog_notify ("Starting get_stageendtime\n");

  @single_stage	= dbsubset (@stage, $stagesub) ;		
  @single_stage	= dbsort(@single_stage, "endtime") ;	# get single record that will be updated
  
  elog_die("No records in stage table matching station $sta \n") if (!dbquery(@single_stage, "dbRECORD_COUNT") ) ; 

  $single_stage[3] 	= dbquery(@single_stage, "dbRECORD_COUNT") - 1 ;	# get last record, which should indicate close time

  $sendtime = dbgetv(@single_stage, qw( endtime ) );
  return($sendtime) ;

}

sub get_stagestarttime {		# get the stage.time

  $stagesub	= "sta=='$sta'&&$chansub&&gtype=~/sensor|seismometer/" ;

  @single_stage	= dbsubset (@stage, $stagesub) ;		
  @single_stage	= dbsort(@single_stage, "time") ;	# get single record that will be updated
  
  elog_die("Found No records in stage table matching station $sta \n") if (!dbquery(@single_stage, "dbRECORD_COUNT") ) ; 

  $single_stage[3] 	= 0 ;	# get first record, which should indicate install time

  $stime = dbgetv(@single_stage, qw( time ) );
  return($stime) ;

}


sub get_wfendtime {		# get the last time of available data from DB 

    @wfdisc	= dbsubset (@wfdisc, $wfsub) ;
    @wfdisc 	= dbsort   (@wfdisc, "endtime") ;	# get single record that will be updated

    elog_die("No records in certified wf db matching $sta for $chansub \n") if (!dbquery(@wfdisc, "dbRECORD_COUNT") ) ; 

    $wfdisc[3] 	= dbquery(@wfdisc, "dbRECORD_COUNT") - 1  ;
    $wfendtime = dbgetv(@wfdisc, qw( endtime ) );
    return($wfendtime);
}

sub modifydlsite {		# modifydlsite($db)		# modify record in dlsite table

  my ($db) = @_; 

  @dlsite = ( $db eq $newdb )  ? @newdlsite : @dlsite ;

# update dlsite table for a comms change
 
  @single_dlsite	= dbsubset (@dlsite, $dlsitesub) ;		# get single record that will be updated

  elog_die("No records in dlsite table matching $dlname with null endtime\n") if (!dbquery(@single_dlsite, "dbRECORD_COUNT") ) ; 
  
  $single_dlsite[3] 	= 0 ;
  ($model,$ssident,$dltime,$idtag,$lat,$lon,$elev)  = dbgetv(@single_dlsite, qw(model ssident time idtag lat lon elev) ) ; 

  if ( ($mytime - 1) > $dltime ) {
     dbputv(@single_dlsite,endtime,$mytime-1);
     elog_notify("Modified dlsite record for sta: $sta in $dbops dlsite table\n")  ;
  } else {
     elog_notify("Time of comms change:  " . &strydtime($mytime) . "\n") ;
     elog_die("Urk...  Check your requested input time!! \n\t Starting time of previous record is:  " . &strydtime($dltime)  ); 
  }

  @dlsite_record = ();
  push(@dlsite_record,
                        "model",   	$model,
                        "ssident",   	$ssident,
                        "time",         $mytime,
                        "dlname",       $dlname,
                        "idtag",        $idtag,
                        "lat",          $lat,
                        "lon",          $lon,
                        "elev",         $elev,
                        "commtype",     $newcommtype,
                        "provider",     $newprovider 
       ) ;

  eval { dbaddv(@dlsite,@dlsite_record) } ;
        if ($@) {
              warn $@;
              elog_complain("Problem adding dlsite record:  $sta, time: ". &strydtime($mytime) . ".\n")  ;
              elog_die("No record added!\n");
        } else {
              elog_notify("Added dlsite record to database: $dbops\n")  ;
        }

}

sub close_deployment {		# close_deployment($db, $endtime,$equip_removal,$decerttime)  record in deployment table

  my ($db, $time1, $time2, $time3) = @_; 

# get deployment.endtime from (last time in wfdisc?  stage.endtime? last data in orb?)
#   chose to use last endtime of wfdisc

# get deployment.equip_remove from (last time in wfdisc?  stage.endtime? last data in orb?)
#   chose to use stage.endtime 
#  NOTE:  if opt_A, -A, deployment.equip_remove is set to NULL

# get deployment.decert from (last time in wfdisc?  stage.endtime? last data in orb? ????)
#   chose to use time from command line

  @deptable =  ($db eq $newdb)   ? @newdeployment : @deployment ;

  elog_notify("Closing record in deployment table: $db \n") if $opt_v ;  

  @single_deployment	= dbsubset (@deptable, $depsub) ;

  elog_die("No records in deployment table matching $sta\n") if (!dbquery(@single_deployment, "dbRECORD_COUNT") ) ; 
  if (dbquery(@single_deployment, "dbRECORD_COUNT") > 1) {
    elog_die("Too many records in deployment table.  Try using -V with a vnet. \n")  if (!$opt_V) ; 
    elog_notify("Attempting subsetting based on vnet. \n") if ($opt_V) ; 
    @single_deployment	= dbsubset (@single_deployment, $vnetsub) ;
    if (dbquery(@single_deployment, "dbRECORD_COUNT") > 1) {
	elog_die("Too many records in deployment table.  Fix your deployment table.\n") ; 
    } 
  }

  $single_deployment[3]	= 0 ;

  dbputv(@single_deployment,endtime,$time1,equip_remove,$time2,decert_time,$time3) ; 

  $mydb = (defined $newdb)  ? $newdb : $db ;
  elog_notify("Closed deployment record in database: $mydb\n")  if ($opt_v) ;

}

sub close_dlsite { 	# &close_dlsite($db,$endtime)		

my ($db,$endtime)  = @_ ;

# get dlsite.endtime from (last time in wfdisc?  stage.endtime? last data in orb?)
#   chose to use stage.endtime

  @dlsite = ( $db eq $newdb )  ? @newdlsite : @dlsite ;

  $dlsitesub	= "$dlstasub && $nullsub";
  @single_dlsite	= dbsubset (@dlsite, $dlsitesub) ;		# get single record that will be updated
  elog_die("No open records in dlsite table matching dlname $dlname\n") if (!dbquery(@single_dlsite, "dbRECORD_COUNT") ) ; 
  elog_die("Too many records in dlsite matching dlname $dlname\n") if (dbquery(@single_dlsite, "dbRECORD_COUNT") > 1) ; 

  $single_dlsite[3] 	= 0 ;

  dbputv(@single_dlsite,endtime,$endtime) ; 
  elog_notify("Closed dlsite record in database: $dbops\n")  if ($opt_v) ;

} 

sub modifycomm {  # &modifycomm($db,$time)		
#HERE

my ($db,$endcommtime)  = @_ ;

  @comm = ( $db eq $newdb )  ? @newcomm : @comm ;

# update comm table
  @single_comm = dbsubset (@comm, $commsub) ;		# get single record that will be updated

  elog_die("No records in comm table matching $sta with null endtime\n") if (!dbquery(@single_comm, "dbRECORD_COUNT") ) ; 
  elog_die("Too many records in comm matching $sta\n") if (dbquery(@single_comm, "dbRECORD_COUNT") > 1) ; 
  $single_comm[3] = 0 ;

  ($ctime,$cendtime,$commtype,$provider) = dbgetv(@single_comm, qw(time endtime commtype provider) );

  if ( $endcommtime > $ctime ) {
     dbputv(@single_comm,endtime,$endcommtime);
     elog_notify("Modified comm  record for sta: $sta in $db comm table\n")  ;
  } else {
     elog_notify("Time of comms change:  " . &strydtime($endcommtime) . "\n") ; 
     elog_die("Urk...  Check your requested input time!! \n\t Starting time of previous record is: " . &strydtime($ctime)  )  ;

  }

}

sub close_comm { # &close_comm($dbops,$time)

  my ($db,$endcommtime) = @_ ;

# update comm table
  @comm = ( $db eq $newdb )  ? @newcomm : @comm ;

  @single_comm = dbsubset (@comm, $commsub) ;		# get single record that will be updated

  elog_die("Too many records in comm matching $sta\n") if (dbquery(@single_comm, "dbRECORD_COUNT") > 1) ; 
  elog_die("No records in comm table matching $sta with null endtime\n") if (!dbquery(@single_comm, "dbRECORD_COUNT") ) ; 
  $single_comm[3] = 0 ;

  ($ctime,$cendtime,$commtype,$provider) = dbgetv(@single_comm, qw(time endtime commtype provider) );

  if ( $endcommtime > $ctime ) {
     dbputv(@single_comm,endtime,$endcommtime);
     elog_notify("Closed comm  record for sta: $sta in $db comm table\n")  if ($opt_v) ;
  } else {
     elog_die("Urk...  Check your requested close time: " . &strydtime($endcommtime) . " !! \n\t Starting time of previous record is: " . &strydtime($ctime)  ); 
  }


}

sub add2dlsite	{	# add2dlsite ($db) 		# add a new record to the dlsite table

  my ($dbops) = @_;

  elog_notify("Starting modification of dlsite via external program q330_location. \n")  ;
  elog_notify("This program assumes sitedb and dbops are the same..... \n")  ;
  $cmd = "q330_location -s $sta $status_orb $cmd_orb $dbops" ;
  &run($cmd)  ;

}

sub add2comm {	#add2comm($db, $sta, $time, $commtype, $provider)		# add a new record to the comm table

  my ($db, $sta, $stime, $commtype, $provider) = @_;

  @comm_record = ();
  push(@comm_record,
                        "sta",   	$sta ,
                        "time",         $stime,
                        "commtype",     $commtype,
                        "provider",     $provider 
        ) ;

  @commtable = ( $db eq $newdb )  ? @newcomm : @comm ;

  elog_notify("Adding record to comm table: $db \n") if $opt_v ;  

  eval { dbaddv(@commtable,@comm_record) };

  if ($@) {
      warn $@;
      elog_complain("Problem adding comm record:  $sta, time: ". &strydtime($stime) . " $commtype $provider to db: $db. \n")  ;
      elog_die("No record added!\n");
  } else {
      elog_notify("Added comm record to database: $db\n")  ;
  }

}

sub add2deployment  {	# ( $db, $vnet, $net, $sta, $time, $equip_install, $cert_time)  add a new record to the deployment table

  my ($db, $vnet, $net, $sta, $time, $install_time, $cert_time)  = @_ ; 

  elog_notify("Db: $db; Vnet: $vnet; Snet: $net; Sta: $sta; \n")  ;

  @dep_record = ();

  push(@dep_record,
	"vnet",   	$vnet,
	"snet",   	$net,
	"sta",   	$sta,
	"time",         $time,
	"endtime", 	$endnull,
	"equip_install", $install_time,
	"equip_remove",	$endnull,
	"cert_time",	$cert_time,
	"decert_time",	$endnull,
	"pdcc",     	$pdcc,
	"sdcc",     	"-"   
  ) ;

  @deptable = ( $db eq $newdb )  ? @newdeployment : @deployment ;

  elog_notify("Adding record to deployment table: $db \n") if $opt_v ;  

  eval { dbaddv(@deptable,@dep_record) };
  if ($@) {
      warn $@;
      elog_complain("Problem adding deployment record:  $vnet, $net, $sta, time: ". &strydtime($time) . " endtime: ". &strydtime($endnull) . ".\n")  ;
      elog_die("No record added!\n");
  } else {
      elog_notify("Added deployment record to database: $db\n")  ;
  }

}

sub add2adoption {	# $add2adoption($db,$time) 		# add a new record to the adoption table 

  my ($db, $time) = @_ ; 

  @adoption= ( $db eq $newdb )  ? @newadoption : @adoption ;

  push(@adoption_record,
                        "snet",		$snet,
                        "sta",		$sta,
                        "time",		$time,
                        "newsnet",	$newnet,
                        "newsta",	$newsta,
                        "atype",	$adopt_phrase,
                        "auth",		$newDCC
       ) ;

  elog_notify("Adding record to adoption table in database: $db\n")  if ($opt_v) ;
  eval { dbaddv(@adoption,@adoption_record) };
  if ($@) {
      warn $@;
      elog_complain("Problem adding adoption record:  $snet, $sta, $newnet, $newsta, time: ". &strydtime($mytime) . ", atype: $atype.\n")  ;
      elog_die("No record added!\n");
  } else {
      elog_notify("Added adoption record to database: $db\n")  ;
  }

}

sub new_sta_net_dcc { 

  #
  # Per agreed upon conventions:
  #	EARN stations will retain their same snet_sta 
  #	TRANSITION stations will likely change their snet_sta
  #	REFNET/Backbone stations will likely retain their same snet_sta 
  #	CEUSN/1N4 stations will change net, keep sta 
  #		if these conventions change, reprogramming may be necessary
  #
  # For now, make the operator choose.  Return will keep original names.
  #

    $newsta	= ask( "New station name ($sta):  " ) ;
    if( $newsta=~ /^\s*$/ ) {
        $newsta= "$sta";
    } 

    $newnet	= ask( "New network code ($snet):  " ) ; 
    if( $newnet=~ /^\s*$/ ) {
        $newnet= "$snet";
    }

    $newDCC   = ask( "Newly responsible data center (????????):  " );
    if( $newDCC=~ /^\s*$/ ) {
        $newDCC= "-";
    }

    return ;
}

sub trim {

        # from Perl Cookbook (O'Reilly) recipe 1.14, p.30

        my @out = @_ ;
        for (@out) {
             s/^\s+//;
             s/\s+$//;
        }
        return wantarray ? @out  : $out[0];
}


sub run {               # run system cmds safely
    my ( $cmd ) = @_ ;
    system ( $cmd ) ;
    if ($?) {
        elog_complain(0, "$cmd error $? \n") ;
        exit(1); 
    }
}


sub usage {
        print STDERR <<END;

   For a new installation:

       USAGE: $0  -I [-k] [-n] [-v] [-V vnet] [-m source_match] [-p pf] [-C cmdORB] [-P prelimORB] [-S statusORB] [-w prelimwfDB] [-s siteDB] dbopsdb snet sta certify_time comm_provider comm_type  \n");

   For a comms update:    

       USAGE: $0 -U [-k] [-p pf] dbopsdb snet sta time_of_comm_change comm_provider [comm_type]  \n");

   For a station removal:

       USAGE: $0 -R [-k] [-p pf] [-W wfDB] [-s siteDB] dbopsdb snet sta decert_time   \n");

   For a station transition to regional network:

       USAGE: $0 -A [-k] [-p pf] [-W wfDB] [-s siteDB] dbopsdb snet sta decert_time   \n");

END
        exit(1);
}

