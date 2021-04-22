
Check this repo out under /srv

    cd /srv/osg-cloud-worker
    ./bootstrap.sh

Add the provided token to /etc/condor/tokens.d/flock.opensciencegrid.org

Create an HTCondor override file in /etc/condor/config.d/99-local.conf

    GLIDEIN_Country = "US"
    GLIDEIN_Site = "Texas Advanced Computing Center"
    GLIDEIN_ResourceName = "TACC-Jetstream-Backfill"
    DEDICATED_USER = "rynge"
    START = (TARGET.Owner == MY.DEDICATED_USER)


