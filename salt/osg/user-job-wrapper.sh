#!/bin/bash


function getPropBool
{
    # $1 the file (for example, $_CONDOR_JOB_AD or $_CONDOR_MACHINE_AD)
    # $2 the key
    # $3 is the default value if unset
    # echo "1" for true, "0" for false/unspecified
    # return 0 for true, 1 for false/unspecified
    default=$3
    if [ "x$default" = "x" ]; then
        default=0
    fi
    val=`(grep -i "^$2 " $1 | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    # convert variations of true to 1
    if (echo "x$val" | grep -i true) >/dev/null 2>&1; then
        val="1"
    fi
    if [ "x$val" = "x" ]; then
        val="$default"
    fi
    echo $val
    # return value accordingly, but backwards (true=>0, false=>1)
    if [ "$val" = "1" ];  then
        return 0
    else
        return 1
    fi
}


function getPropStr
{
    # $1 the file (for example, $_CONDOR_JOB_AD or $_CONDOR_MACHINE_AD)
    # $2 the key
    # $3 default value if unset
    default="$3"
    val=`(grep -i "^$2 " $1 | cut -d= -f2 | sed "s/[\"' \t\n\r]//g") 2>/dev/null`
    if [ "x$val" = "x" ]; then
        val="$default"
    fi
    echo $val
}


# The following four functions are based mostly on Carl Edquist's code

setmatch () {
  local __=("$@")
  set -- "${BASH_REMATCH[@]}"
  shift
  eval "${__[@]}"
}

rematch () {
  [[ $1 =~ $2 ]] || return 1
  shift 2
  setmatch "$@"
}

get_vars_from_env_str () {
  local str_arr condor_var_string=""
  env_str=${env_str#'"'}
  env_str=${env_str%'"'}
  # Strip out escaped whitespace
  while rematch "$env_str" "(.*)'([[:space:]]+)'(.*)" env_str='$1$3'
  do :; done

  # Now, split the string on whitespace
  read -ra str_arr <<<"${env_str}"

  # Finally, parse each element of the array.
  # They should each be name=value assignments,
  # and we only need to grab the name
  vname_regex="(^[_a-zA-Z][_a-zA-Z0-9]*)(=)[.]*"
  for assign in "${str_arr[@]}"; do
      if [[ "$assign" =~ $vname_regex ]]; then
	  condor_var_string="$condor_var_string ${BASH_REMATCH[1]}"
      fi
  done
  echo "$condor_var_string"
}

parse_env_file () {
    shopt -s nocasematch
    while read -r attr eq env_str; do
	if [[ $attr = Environment && $eq = '=' ]]; then
	    get_vars_from_env_str
	    break
	fi
    done < "$1"
    shopt -u nocasematch
}

shutdown_glidein() {
    # To be called when a severe error is encountered. It will
    # result in the glidin stopping taking jobs and eventually
    # shuts down.
    # $1 error message

    echo "$1" 1>&2
    # error to _CONDOR_WRAPPER_ERROR_FILE
    # https://htcondor.readthedocs.io/en/latest/admin-manual/configuration-macros.html?highlight=_CONDOR_WRAPPER_ERROR_FILE#condor-starter-configuration-file-entries
    if [ "x$_CONDOR_WRAPPER_ERROR_FILE" != "x" ]; then
        echo "$1" >>$_CONDOR_WRAPPER_ERROR_FILE
    fi
    if [ "x$GWMS_DEBUG" = "x" ]; then
        # if we are not debugging, shutdown
        touch ../../.stop-glidein.stamp >/dev/null 2>&1
        sleep 20m
    fi
    exit 90
}


# ensure all jobs have PATH set
# bash can set a default PATH - make sure it is exported
export PATH=$PATH
if [ "x$PATH" = "x" ]; then
    export PATH="/usr/local/bin:/usr/bin:/bin"
fi

# clean up potential leftovers from previous runs
rm -f .singularity.startup-ok

# SINGULARITY_CONTAINER as --cleanenv does not propate REXEC variable
if [ "x$OSG_SINGULARITY_REEXEC" = "x" -a "x$SINGULARITY_CONTAINER" = "x" ]; then
    
    if [ "x$_CONDOR_JOB_AD" = "x" ]; then
        export _CONDOR_JOB_AD="NONE"
    fi
    if [ "x$_CONDOR_MACHINE_AD" = "x" ]; then
        export _CONDOR_MACHINE_AD="NONE"
    fi

    # make sure the job can access certain information via the environment, for example ProjectName
    export OSGVO_PROJECT_NAME=$(getPropStr $_CONDOR_JOB_AD ProjectName)
    export OSGVO_SUBMITTER=$(getPropStr $_CONDOR_JOB_AD User)
    
    # "save" some setting from the condor ads - we need these even if we get re-execed
    # inside singularity in which the paths in those env vars are wrong
    # Seems like arrays do not survive the singularity transformation, so set them
    # explicity

    export HAS_SINGULARITY=$(getPropBool $_CONDOR_MACHINE_AD HAS_SINGULARITY 0)
    export OSG_SINGULARITY_PATH=$(getPropStr $_CONDOR_MACHINE_AD OSG_SINGULARITY_PATH)
    export OSG_SINGULARITY_IMAGE_DEFAULT=$(getPropStr $_CONDOR_MACHINE_AD OSG_SINGULARITY_IMAGE_DEFAULT)
    export OSG_SINGULARITY_IMAGE=$(getPropStr $_CONDOR_JOB_AD SingularityImage)
    export OSG_SINGULARITY_AUTOLOAD=$(getPropBool $_CONDOR_JOB_AD SingularityAutoLoad 1)
    export OSG_SINGULARITY_BIND_CVMFS=$(getPropBool $_CONDOR_JOB_AD SingularityBindCVMFS 1)
    export OSG_SINGULARITY_CLEAN_ENV=$(getPropBool $_CONDOR_JOB_AD SingularityCleanEnv 0)

    export STASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsStashCache 0)
    export STASHCACHE_WRITABLE=$(getPropBool $_CONDOR_JOB_AD WantsStashCacheWritable 0)

    export POSIXSTASHCACHE=$(getPropBool $_CONDOR_JOB_AD WantsPosixStashCache 0)

    # Don't load modules for LIGO
    if (echo "X$GLIDEIN_Client" | grep ligo) >/dev/null 2>&1; then
        export InitializeModulesEnv=$(getPropBool $_CONDOR_JOB_AD InitializeModulesEnv 0)
    else
        export InitializeModulesEnv=$(getPropBool $_CONDOR_JOB_AD InitializeModulesEnv 1)
    fi
    export LoadModules=$(getPropStr $_CONDOR_JOB_AD LoadModules)

    export LMOD_BETA=$(getPropBool $_CONDOR_JOB_AD LMOD_BETA 0)
    
    export OSG_MACHINE_GPUS=$(getPropStr $_CONDOR_MACHINE_AD GPUs "0")

    # http_proxy from our advertise script
    export http_proxy=$(getPropStr $_CONDOR_MACHINE_AD http_proxy)
    if [ "x$http_proxy" = "x" ]; then
        unset http_proxy
    fi

    # do not use $HOME for caching
    export SINGULARITY_CACHEDIR=$PWD/.singularity-cache
    mkdir -p $SINGULARITY_CACHEDIR

    if [ "x$OSG_SINGULARITY_AUTOLOAD" != "x1" ]; then
        echo "Warning: Using +SingularityAutoLoad is no longer allowed. Ignoring." 1>&2
        export OSG_SINGULARITY_AUTOLOAD=0
    fi

    #############################################################################
    #
    #  Singularity
    #
    if [ "x$HAS_SINGULARITY" = "x1" -a "x$OSG_SINGULARITY_PATH" != "x" ]; then

        # If  image is not provided, load the default one
        # Custom URIs: http://singularity.lbl.gov/user-guide#supported-uris
        if [ "x$OSG_SINGULARITY_IMAGE" = "x" ]; then
            # Default
            export OSG_SINGULARITY_IMAGE="$OSG_SINGULARITY_IMAGE_DEFAULT"
            export OSG_SINGULARITY_BIND_CVMFS=1
        fi

        # ensure we are only accessing images from CVMFS
        if (echo "$OSG_SINGULARITY_IMAGE" | grep -v '^/cvmfs') >/dev/null 2>&1; then
            echo "Error: Container images have to be loaded from /cvmfs" 1>&2
            exit 90
        fi

        # check that the image is actually available (but only for /cvmfs ones)
        if (echo "$OSG_SINGULARITY_IMAGE" | grep '^/cvmfs') >/dev/null 2>&1; then
            if ! ls -l "$OSG_SINGULARITY_IMAGE" >/dev/null; then
                # if we get here, it could either be a user error (wrong path
                # to an image for example, or that CVMFS crapped out since
                # testing. We will use a crude test to determine how to handle
                # the error.
                if ! ls -l "/cvmfs/singularity.opensciencegrid.org/opensciencegrid/" >/dev/null 2>&1; then
                    shutdown_glidein "Error: unable to access CVMFS! ($OSG_SINGULARITY_IMAGE)"
                else
                    # goes to users stderr
                    echo "Error: unable to access $OSG_SINGULARITY_IMAGE" 1>&2
                    exit 90
                fi
            fi
        fi

        # put a human readable version of the image in the env before
        # expanding it - useful for monitoring
        export OSG_SINGULARITY_IMAGE_HUMAN="$OSG_SINGULARITY_IMAGE"

        # for /cvmfs based directory images, expand the path without symlinks so that
        # the job can stay within the same image for the full duration
        if echo "$OSG_SINGULARITY_IMAGE" | grep /cvmfs >/dev/null 2>&1; then
            if (cd $OSG_SINGULARITY_IMAGE) >/dev/null 2>&1; then
                NEW_IMAGE_PATH=`(cd $OSG_SINGULARITY_IMAGE && pwd -P) 2>/dev/null`
                if [ "x$NEW_IMAGE_PATH" != "x" ]; then
                    OSG_SINGULARITY_IMAGE="$NEW_IMAGE_PATH"
                fi
            fi
        fi

	    # ddavila 20190510:
        # If condor_chirp is present, then copy it inside the container.
        if [ -e ../../main/condor/libexec/condor_chirp ]; then
            mkdir -p condor/libexec
            cp ../../main/condor/libexec/condor_chirp condor/libexec/condor_chirp
            mkdir -p condor/lib
            cp -r ../../main/condor/lib condor/
        fi

        # set up the env to make sure Singularity uses the glidein dir for exported /tmp, /var/tmp
        if [ "x$GLIDEIN_Tmp_Dir" != "x" -a -e "$GLIDEIN_Tmp_Dir" ]; then
            if mkdir $GLIDEIN_Tmp_Dir/singularity-work.$$ ; then
                export SINGULARITY_WORKDIR=$GLIDEIN_Tmp_Dir/singularity-work.$$
            fi
        fi
        
        OSG_SINGULARITY_EXTRA_OPTS=""
   
        # cvmfs access inside container (default, but optional)
        if [ "x$OSG_SINGULARITY_BIND_CVMFS" = "x1" ]; then
            OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --bind /cvmfs"
        fi

        # clean environment if user wants it
        if [ "x$OSG_SINGULARITY_CLEAN_ENV" = "x1" ]; then
            OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --cleanenv"
        fi

        # Binding different mounts
        for MNTPOINT in \
            /hadoop \
            /ceph \
            /hdfs \
            /lizard \
            /mnt/hadoop \
            /mnt/hdfs \
        ; do
            if [ -e $MNTPOINT/. -a -e $OSG_SINGULARITY_IMAGE/$MNTPOINT ]; then
                OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --bind $MNTPOINT"
            fi
        done

        # GPUs - bind outside GPU library directory to inside /host-libs
        if [ $OSG_MACHINE_GPUS -gt 0 ]; then
            # check if the image on cvmfs has /.singularity/libs
            if (echo "$OSG_SINGULARITY_IMAGE" | grep '^/cvmfs') >/dev/null 2>&1; then
                if ! ls -l "$OSG_SINGULARITY_IMAGE/.singularity.d/libs/" >/dev/null 2>&1; then
                    echo "OSG Singularity wrapper: The container does not have a /.singularity.d/libs directory - NVIDIA GPU binding of libraries will probably not work." 1>&2
                fi
                # some versions of Singulariy does not bind /etc/OpenCL/vendors
                if [ -e "$OSG_SINGULARITY_IMAGE/etc/OpenCL" ]; then
                    OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --bind /etc/OpenCL/vendors"
                fi
            fi
            OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --nv"
            # --nv does not update LD_LIBRARY_PATH in some versions
            export SINGULARITYENV_LD_LIBRARY_PATH=/.singularity.d/libs:$SINGULARITYENV_LD_LIBRARY_PATH
        else
            # if not using gpus, we can limit the image more
            OSG_SINGULARITY_EXTRA_OPTS="$OSG_SINGULARITY_EXTRA_OPTS --contain"
        fi

        # We want to bind $PWD to /srv within the container - however, in order
        # to do that, we have to make sure everything we need is in $PWD, most
        # notably the user-job-wrapper.sh (this script!)
        cp $0 .osgvo-user-job-wrapper.sh

        # Remember what the outside pwd dir is so that we can rewrite env vars
        # pointing to omewhere inside that dir (for example, X509_USER_PROXY)
        export OSG_SINGULARITY_OUTSIDE_PWD="$PWD"
        if [ "x$_CONDOR_JOB_IWD" != "x" ]; then
            export OSG_SINGULARITY_OUTSIDE_PWD="$_CONDOR_JOB_IWD"
        fi

        # build a new command line, with updated paths
        CMD=()
        for VAR in "$@"; do
            # Two seds to make sure we catch variations of the iwd,
            # including symlinked ones. The leading space is to prevent
            # echo to interpret dashes.
            VAR=`echo " $VAR" | sed -E "s;$PWD(.*);/srv\1;" | sed -E "s;.*/execute/dir_[0-9a-zA-Z]*(.*);/srv\1;" | sed -E "s;^ ;;"`
            CMD+=("$VAR")
        done

        if [ "x$LD_LIBRARY_PATH" != "x" ]; then
            if [ "x$GWMS_DEBUG" != "x" ]; then
                echo "OSG Singularity wrapper: LD_LIBRARY_PATH is set to $LD_LIBRARY_PATH outside Singularity. This will not be propagated to inside the container instance." 1>&2
            fi
            unset LD_LIBRARY_PATH
        fi
        
        if [ "x$LD_PRELOAD" != "x" ]; then
            if [ "x$GWMS_DEBUG" != "x" ]; then
                echo "OSG Singularity wrapper: LD_PRELOAD is set to $LD_PRELOAD outside Singularity. Unsetting it." 1>&2
            fi
            unset LD_PRELOAD
        fi

        export OSG_SINGULARITY_REEXEC=1
        export SINGULARITYENV_OSG_SINGULARITY_REEXEC=1

        # If we are cleaning the environment, then we also need to export
        # variables that will be transformed into certain critical variables
        # inside the container. Note, we don't deal with PATH, which requires
        # requires some care, as a user could conceivably set not just
        # SINGULARITYENV_PATH, but also either of SINGULARITYENV_PREPEND_PATH
        # or SINGULARITYENV_APPEND_PATH.
        #
        # The list of variables below that are transformed should be any variable
        # that is exported during the first execution of this script (above), or
        # which is inspected or manipulated during the second execution of this
        # script.  Maybe also others...
        #
        # Note on future proofing: if additional variables are exported above
        # or referenced during the second execution of this script, they will
        # also need to be added to this list.  I don't know an elegant way
        # to automate that process.
        if [ "x$OSG_SINGULARITY_CLEAN_ENV" = "x1" ]; then

            OSG_SINGULARITY_ENVVARS="OSG_SINGULARITY_REEXEC \
                _CHIRP_DELAYED_UPDATE_PREFIX \
                CONDOR_PARENT_ID \
                GLIDEIN_ResourceName \
                GLIDEIN_Site \
                HAS_SINGULARITY \
                http_proxy \
                InitializeModulesEnv \
                LIGO_DATAFIND_SERVER \
                OSG_MACHINE_GPUS \
                OSG_SINGULARITY_AUTOLOAD \
                OSG_SINGULARITY_BIND_CVMFS \
                OSG_SINGULARITY_CLEAN_ENV \
                OSG_SINGULARITY_IMAGE \
                OSG_SINGULARITY_IMAGE_DEFAULT \
                OSG_SINGULARITY_IMAGE_HUMAN \
                OSG_SINGULARITY_OUTSIDE_PWD \
                OSG_SINGULARITY_PATH \
                OSG_SITE_NAME \
                OSGVO_PROJECT_NAME \
                OSGVO_SUBMITTER \
                OSG_WN_TMP \
                POSIXSTASHCACHE \
                SINGULARITY_WORKDIR \
                STASHCACHE \
                STASHCACHE_WRITABLE \
                TZ \
                X509_USER_CERT \
                X509_USER_KEY \
                X509_USER_PROXY"

            # Determine all the _CONDOR_* variable names
            OSG_SINGULARITY_ENVVARS="$OSG_SINGULARITY_ENVVARS $(env -0 | tr '\n' '\\n' | tr '\0' '\n' | tr '=' ' ' | awk '{print $1;}' | grep ^_CONDOR_)"

            # Determine all the environment variables from the job ClassAd
            if [ -e "$_CONDOR_JOB_AD" ]; then
                _ALL_CONDOR_SET_VARNAMES=$(parse_env_file "$_CONDOR_JOB_AD")
		_SING_ENV_CONDOR_SET_VARNAMES=""
		_sing_regex="^SINGULARITYENV_"
		for varname in ${_ALL_CONDOR_SET_VARNAMES}; do
		    if [[ "$varname" =~ $_sing_regex ]]; then
			_SING_ENV_CONDOR_SET_VARNAMES="$_SING_ENV_CONDOR_SET_VARNAMES $varname"
		    else
			OSG_SINGULARITY_ENVVARS="$OSG_SINGULARITY_ENVVARS $varname"
		    fi
		done
		# If the user set variables of the form SINGULARITYENV_VARNAME,
		# then warn them and unset those variables
		if [ -n "${_SING_ENV_CONDOR_SET_VARNAMES}" ]; then
		    echo "The following variables beginning with 'SINGULARITYENV_' were set " \
                         "in the condor submission file and will not be propagated: " \
			 "${_SING_ENV_CONDOR_SET_VARNAMES}" 1>&2
		    for varname in ${_SING_ENV_CONDOR_SET_VARNAMES}; do
			unset $varname
		    done
		fi
            fi

            for varname in $OSG_SINGULARITY_ENVVARS; do
                # If any of the variables above are unset, we don't want to
                # accidentally propagate that into the container as set but empty.
                # Note the test below could be simplified in bash 4.2+, but not
                # sure what we can assume.
                if [ ! -z ${!varname+x} ]; then
                    newname="SINGULARITYENV_${varname}"
                    # If there's already a variable of the form SINGULARITYENV_varname set,
                    # then do nothing.  Unsure if this should  be removed if setting up
                    # the condor-specified environment inside the container is implemented.
                    if [ -z ${!newname+x} ]; then
                        export $newname=${!varname}
                    fi
                fi
            done
        fi

        # if debugging, dump the command line on stderr
        if [ "x$GWMS_DEBUG" != "x" ]; then
            echo "$OSG_SINGULARITY_PATH exec $OSG_SINGULARITY_EXTRA_OPTS --bind $PWD:/srv --no-home --ipc --pid $OSG_SINGULARITY_IMAGE /srv/.osgvo-user-job-wrapper.sh ${CMD[@]}" 1>&2
        fi

        $OSG_SINGULARITY_PATH exec $OSG_SINGULARITY_EXTRA_OPTS \
                              --bind $PWD:/srv \
                              --no-home --ipc --pid \
                              "$OSG_SINGULARITY_IMAGE" \
                              /srv/.osgvo-user-job-wrapper.sh \
                              "${CMD[@]}"
        EC=$?
        if [ $EC -ne 0 ]; then
            # was it a Singularity issue or a user job issue?
            #if [ ! -e .singularity.startup-ok ]; then
            #    shutdown_glidein "Singularity encountered an error starting the container"
            #fi
            exit 90
        fi
        # do not delete in debug - used for testing
        if [ "x$GWMS_DEBUG" = "x" ]; then
            rm -f .singularity.startup-ok
        fi
        exit $EC
    fi

else
    # we are now inside singularity

    # need to start in /srv (Singularity's --pwd is not reliable)
    cd /srv

    # fix up the env
    export HOME=/srv
    unset TMP
    unset TMPDIR
    unset TEMP
    unset X509_CERT_DIR
    unset LD_PRELOAD
    for key in X509_USER_PROXY X509_USER_CERT \
               _CONDOR_CREDS _CONDOR_MACHINE_AD \
               _CONDOR_EXECUTE _CONDOR_JOB_AD \
               _CONDOR_SCRATCH_DIR _CONDOR_CHIRP_CONFIG _CONDOR_JOB_IWD \
               OSG_WN_TMP ; do
        eval val="\$$key"
        val=`echo "$val" | sed -E "s;$OSG_SINGULARITY_OUTSIDE_PWD(.*);/srv\1;"`
        eval $key=$val
    done

    # If X509_USER_PROXY and friends are not set by the job, we might see the
    # glidein one - in that case, just unset the env var
    for key in X509_USER_PROXY X509_USER_CERT X509_USER_KEY ; do
        eval val="\$$key"
        if [ "x$val" != "x" ]; then
            if [ ! -e "$val" ]; then
                eval unset $key >/dev/null 2>&1 || true
            fi
        fi
    done

    # override some OSG specific variables
    if [ "x$OSG_WN_TMP" != "x" ]; then
        export OSG_WN_TMP=/tmp
    fi

    # ddavila 20190510:
    # Add Chirp back to the environment
    if [ -e $PWD/condor/libexec/condor_chirp ]; then
        export PATH=$PWD/condor/libexec:$PATH
        export LD_LIBRARY_PATH=$PWD/condor/lib:$LD_LIBRARY_PATH
    fi

    # Some java programs have seen problems with the timezone in our containers.
    # If not already set, provide a default TZ
    if [ "x$TZ" = "x" ]; then
        export TZ="UTC"
    fi

    # signal our parent that we got here
    touch .singularity.startup-ok
fi 



#############################################################################
#
#  modules and env 
#

# prepend HTCondor libexec dir so that we can call chirp
if [ -e ../../main/condor/libexec ]; then
    DER=`(cd ../../main/condor/libexec; pwd)`
    export PATH=$DER:$PATH
fi

# load modules, if available
if [ "x$InitializeModulesEnv" = "x1" ]; then
    if [ "x$LMOD_BETA" = "x1" ]; then
        # used for testing the new el6/el7 modules 
        if [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh -a -e /cvmfs/connect.opensciencegrid.org/modules/spack/share/spack/setup-env.sh ]; then
            . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-beta-init.sh
        fi
    elif [ -e /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh -a -e /cvmfs/connect.opensciencegrid.org/modules/spack/share/spack/setup-env.sh ]; then
        . /cvmfs/oasis.opensciencegrid.org/osg/sw/module-init.sh
    fi
fi


# fix discrepancy for Squid proxy URLs
if [ "x$GLIDEIN_Proxy_URL" = "x" -o "$GLIDEIN_Proxy_URL" = "None" ]; then
    if [ "x$OSG_SQUID_LOCATION" != "x" -a "$OSG_SQUID_LOCATION" != "None" ]; then
        export GLIDEIN_Proxy_URL="$OSG_SQUID_LOCATION"
    fi
fi


#############################################################################
#
#  Stash cache 
#

function setup_stashcp {
  # if we do not have stashcp in the path (in the container for example),
  # load stashcache and xrootd from modules
  if ! which stashcp >/dev/null 2>&1; then
      module load stashcache >/dev/null 2>&1 || module load stashcp >/dev/null 2>&1
  fi
}
 
# Check for PosixStashCache first
if [ "x$POSIXSTASHCACHE" = "x1" ]; then
  setup_stashcp
 
  # Add the LD_PRELOAD hook
  export LD_PRELOAD=$MODULE_XROOTD_BASE/lib64/libXrdPosixPreload.so:$LD_PRELOAD
 
  # Set proxy for virtual mount point
  # Format: cache.domain.edu/local_mount_point=/storage_path
  # E.g.: export XROOTD_VMP=data.ci-connect.net:/stash=/
  # Currently this points _ONLY_ to the OSG Connect source server
  export XROOTD_VMP=$(stashcp --closest | cut -d'/' -f3):/stash=/
 
elif [ "x$STASHCACHE" = "x1" -o "x$STASHCACHE_WRITABLE" = "x1" ]; then
  setup_stashcp
fi


#############################################################################
#
#  Load user specified modules
#

if [ "X$LoadModules" != "X" ]; then
    ModuleList=`echo $LoadModules | sed 's/^LoadModules = //i' | sed 's/"//g'`
    for Module in $ModuleList; do
        module load $Module
    done
fi


#############################################################################
#
#  Trace callback
#

if [ ! -e .trace-callback ]; then
    (wget -nv -O .trace-callback http://osg-vo.isi.edu/osg/agent/trace-callback && chmod 755 .trace-callback) >/dev/null 2>&1 || /bin/true
fi
./.trace-callback start >/dev/null 2>&1 || /bin/true


#############################################################################
#
#  Cleanup
#

rm -f .trace-callback .osgvo-user-job-wrapper.sh >/dev/null 2>&1 || true


#############################################################################
#
#  Run the real job
#
exec "$@"
error=$?
echo "Failed to exec($error): $@" > $_CONDOR_WRAPPER_ERROR_FILE
exit 90



