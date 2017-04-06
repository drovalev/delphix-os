#!/usr/bin/ksh -p

#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright (c) 2017 by Delphix. All rights reserved.
#

. $STF_SUITE/tests/functional/pool_checkpoint/pool_checkpoint.kshlib

#
# DESCRIPTION:
# 	Discard checkpoint on a stressed pool. Ensure that we can
#	export and import the pool while discarding but not run any
#	operations that have to do with the checkpoint or change the
#	pool's config.
#
# STRATEGY:
#	1. Create pool
#	2. Attempt to fragment it by doing random writes
#	3. Take checkpoint
#	4. Do more random writes to "free" checkpointed blocks
#	5. Start discarding checkpoint
#	6. Export pool while discarding checkpoint
#	7. Attempt to rewind (should fail)
#	8. Import pool and ensure that discard is still running
#	9. Attempt to run checkpoint commands, or commands that
#	   change the pool's config (should fail)
#

verify_runnable "global"

function test_cleanup
{
	# reset memory limit to 16M
	mdb_ctf_set_int zfs_spa_discard_memory_limit 1000000
	cleanup
}

setup_pool

log_onexit test_cleanup

#
# Force discard to happen slower so it spans over
# multiple txgs.
#
# Set memory limit to 128 bytes. Assuming that we
# use 64-bit words for encoding space map entries,
# ZFS will discard 8 non-debug entries per txg
# (so at most 16 space map entries in debug-builds
# due to debug entries).
#
# That should give us more than enough txgs to be
# discarding the checkpoint for a long time as with
# the current setup the checkpoint space maps should
# have tens of thousands of entries.
#
mdb_ctf_set_int zfs_spa_discard_memory_limit 0t128

fragment_before_checkpoint

log_must zpool checkpoint $TESTPOOL

fragment_after_checkpoint_and_verify

log_must zpool checkpoint -d $TESTPOOL

log_must zpool export $TESTPOOL

#
# Verify on-disk state while pool is exported
#
log_must zdb -e -p $TMPDIR $TESTPOOL

#
# Attempt to rewind on a pool that is discarding
# a checkpoint.
#
log_mustnot zpool import -d $TMPDIR --rewind-to-checkpoint $TESTPOOL

log_must zpool import -d $TMPDIR $TESTPOOL

#
# Discarding should continue after import, so
# all the following operations should fail.
#
log_mustnot zpool checkpoint $TESTPOOL
log_mustnot zpool checkpoint -d $TESTPOOL
log_mustnot zpool remove $TESTPOOL $DISK1
log_mustnot zpool reguid $TESTPOOL

# reset memory limit to 16M
mdb_ctf_set_int zfs_spa_discard_memory_limit 1000000

wait_discard_finish

log_must zdb $TESTPOOL

log_pass "Can export/import but not rewind/checkpoint/discard or " \
    "change pool's config while discarding."
