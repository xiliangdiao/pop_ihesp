#! /bin/csh -f

if !(-d $EXEROOT/ocn/obj   ) mkdir -p $EXEROOT/ocn/obj    || exit 2
if !(-d $EXEROOT/ocn/source) mkdir -p $EXEROOT/ocn/source || exit 3 

if ($POP_AUTO_DECOMP == 'true') then
  @ ntasks = $NTASKS_OCN / $NINST_OCN
  cd $CASEBUILD
  set config = `env UTILROOT=$UTILROOT ./generate_pop_decomp.pl -res $OCN_GRID \
                                 -nproc $ntasks -thrds $NTHRDS_OCN -output all`
  cd $CASEROOT 
  if ($config[1] >= 0) then
    # Make this all one command, because xmlchange init is slow.
    ./xmlchange POP_BLCKX=$config[3],POP_BLCKY=$config[4],POP_MXBLCKS=$config[5],POP_DECOMPTYPE=$config[6],POP_NX_BLOCKS=$config[7],POP_NY_BLOCKS=$config[8] || exit -1
    # need to do this since env_build.xml just changed
    source $CASEROOT/Tools/ccsm_getenv
  else
    echo "ERROR configure: pop decomp not set for $OCN_GRID on $ntasks x       \
                           $NTHRDS_OCN procs"
    exit -1
  endif
endif

if !(-d $CASEBUILD/popconf) mkdir $CASEBUILD/popconf || exit 1
cd $CASEBUILD/popconf || exit -1

if (($GET_REFCASE == 'TRUE') && ($RUN_TYPE != 'startup') &&                    \
    ($CONTINUE_RUN == 'FALSE')) then
  # During prestage step, rpointer files are copied from refdir
  # Get rid of old rpointer files if they exist and copy them 
  # independently of the prestage.  This is needed for rerunability
  # of cases from REFCASE data for first run
  rm -f $RUNDIR/rpointer.ocn* >&! /dev/null
  set refdir = "ccsm4_init/$RUN_REFCASE/$RUN_REFDATE"
  cp -f $DIN_LOC_ROOT/$refdir/rpointer.ocn* $RUNDIR/
  chmod u+w $RUNDIR/rpointer.ocn* >&! /dev/null
endif

set default_ocn_in_filename = "pop_in"
set inst_counter = 1

while ($inst_counter <= $NINST_OCN)

  if ($NINST_OCN > 1) then
    set inst_string = `printf _%04d $inst_counter`
  else
    set inst_string = ""
  endif
  
  set ocn_in_filename = ${default_ocn_in_filename}${inst_string}
  
  if ($NINST_OCN > 1) then
    # If multi-instance case does not have restart file, use single-case restart
    # for each instance
    foreach suffix ( ovf restart tavg )
      echo "Looking to see if rpointer.ocn.${suffix} exists and rpointer.ocn${inst_string}.${suffix} does not..."
      if (! -e $RUNDIR/rpointer.ocn${inst_string}.${suffix} && -e $RUNDIR/rpointer.ocn.${suffix}) then
        cp -v $RUNDIR/rpointer.ocn.${suffix} $RUNDIR/rpointer.ocn${inst_string}.${suffix}
      endif
    end # foreach
  endif

  # env variable declaring type of restart file (nc vs bin) is not in any xml files
  # but is needed by pop's build-namelist; it comes from rpointer.ocn.restart, which
  # is in $RUNDIR for continued runs, but is in $refdir for hybrid / branch runs
  # that are not continuations
  setenv RESTART_INPUT_TS_FMT 'bin'
  if ($RUN_TYPE == startup && $CONTINUE_RUN == 'FALSE') then
    set check_pointer_file = 'FALSE'
  else
    set check_pointer_file = 'TRUE'
  endif
  
  if (($GET_REFCASE == 'TRUE') && ($RUN_TYPE != 'startup') && ($CONTINUE_RUN == 'FALSE')) then
    # During prestage step, rpointer files are copied from refdir
    set refdir = "ccsm4_init/$RUN_REFCASE/$RUN_REFDATE"
    set pointer_file = "$DIN_LOC_ROOT/$refdir/rpointer.ocn${inst_string}.restart"
    if (! -e $pointer_file) then
      set pointer_file = "$RUNDIR/rpointer.ocn${inst_string}.restart"
    endif
  else
    set pointer_file = "$RUNDIR/rpointer.ocn${inst_string}.restart"
  endif
  
  if ($check_pointer_file == 'TRUE') then
    grep 'RESTART_FMT=' $pointer_file >&! /dev/null
    if ($status == 0) then
      echo "Getting init_ts_file_fmt from $pointer_file"
      setenv RESTART_INPUT_TS_FMT `grep RESTART_FMT= $pointer_file | cut -c13-15`
    endif
  endif

  if (-e $CASEROOT/user_nl_pop${inst_string})                                 \
    $UTILROOT/Tools/user_nlcreate                                              \
               -user_nl_file $CASEROOT/user_nl_pop${inst_string}              \
               -namelist_name pop_inparm >! $CASEBUILD/popconf/cesm_namelist 
  
  # Check to see if "-preview" flag should be passed
  if ( $?PREVIEW_NML ) then
    set PREVIEW_FLAG = "-preview"
  else
    set PREVIEW_FLAG = ""
  endif

  # Check to see if build-namelist exists in SourceMods
  if (-e $CASEROOT/SourceMods/src.pop/build-namelist) then
    set BLD_NML_DIR = $CASEROOT/SourceMods/src.pop
    set CFG_FLAG = "-cfg_dir $CODEROOT/ocn/pop/bld"
  else
    set BLD_NML_DIR = $CODEROOT/ocn/pop/bld
    set CFG_FLAG = ""
  endif
  
  $BLD_NML_DIR/build-namelist $CFG_FLAG $PREVIEW_FLAG                          \
            -infile $CASEBUILD/popconf/cesm_namelist                          \
            -caseroot $CASEROOT                                                \
            -casebuild $CASEBUILD                                              \
            -scriptsroot $SCRIPTSROOT \
            -inst_string "$inst_string" \
            -ocn_grid "$OCN_GRID" || exit -1  

  if (-d ${RUNDIR}) then
    cp $CASEBUILD/popconf/pop_in ${RUNDIR}/$ocn_in_filename || exit -2
  endif

  if (-f $RUNDIR/pop_in${inst_string})                                        \
    rm $RUNDIR/pop_in${inst_string}

  cp -fp $CASEBUILD/popconf/pop_in                                           \
         ${RUNDIR}/pop_in${inst_string}
  cp -fp $CASEBUILD/popconf/${OCN_GRID}_tavg_contents                         \
         ${RUNDIR}/${OCN_GRID}_tavg_contents

  @ inst_counter = $inst_counter + 1

end  # inst_counter




