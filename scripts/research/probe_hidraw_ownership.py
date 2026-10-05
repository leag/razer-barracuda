#!/usr/bin/env python3
"""Probe hidraw aggregate open/close semantics using an external kernel source.

Compiles the source's unmodified hidraw_open and drop_ref functions with minimal
userspace stubs. This is a sequential counterexample, not an endpoint, locking,
or kernel lifecycle test. No device is opened and no source is downloaded.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


STUBS = r'''
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
struct inode { unsigned int minor; };
struct file { void *private_data; };
struct hidraw {
    int exist, open, minor, list_lock, list, wait;
    void *hid;
};
struct hidraw_list { struct hidraw *hidraw; int read_mutex, node; };
static struct hidraw *hidraw_table[1];
static int opens, closes, owner;
#define iminor(i) ((i)->minor)
#define kzalloc_obj(t) calloc(1, sizeof(t))
#define kzalloc(n, flags) calloc(1, (n))
#define kfree(p) free(p)
#define down_write(p) ((void)0)
#define up_write(p) ((void)0)
#define mutex_init(p) ((void)0)
#define spin_lock_irqsave(p, flags) ((flags) = 0)
#define spin_unlock_irqrestore(p, flags) ((void)(flags))
#define list_add_tail(n, l) ((void)0)
#define wake_up_interruptible(p) ((void)0)
#define device_destroy(c, d) ((void)0)
#define PM_HINT_FULLON 1
#define PM_HINT_NORMAL 0
static int hid_hw_power(void *device, int hint) { return 0; }
/* Give the driver the strongest possible rejecting open callback. */
static int hid_hw_open(void *device) {
    opens++;
    if (owner) return -EBUSY;
    owner = 1;
    return 0;
}
static void hid_hw_close(void *device) { closes++; owner = 0; }
'''

SCENARIOS = r'''
int main(void) {
    struct inode inode = {0};
    struct file first = {0}, second = {0};
    struct hidraw device = {.exist = 1};
    hidraw_table[0] = &device;
    assert(hidraw_open(&inode, &first) == 0);
    assert(owner == 1 && opens == 1);
    /* A different open file description bypasses the rejecting callback. */
    assert(hidraw_open(&inode, &second) == 0);
    assert(first.private_data != second.private_data);
    assert(device.open == 2 && opens == 1);
    puts("Second independent open accepted; driver open callbacks: 1");
    drop_ref(&device, 0);
    free(first.private_data);
    assert(device.open == 1 && closes == 0 && owner == 1);
    puts("First owner closes; driver close callbacks: 0");
    drop_ref(&device, 0);
    free(second.private_data);
    assert(device.open == 0 && closes == 1 && owner == 0);
    puts("Last independent client closes; driver close callbacks: 1");
    /* Disconnect closes hardware while an open description remains. */
    assert(hidraw_open(&inode, &first) == 0);
    drop_ref(&device, 1);
    assert(device.exist == 0 && device.open == 1 && closes == 2);
    free(first.private_data);
    puts("Disconnect closes hardware with a client still open");
    puts("RESULT: aggregate callbacks do not enforce an exclusive file owner");
    return 0;
}
'''


def function(source, signature):
    """Extract a top-level kernel function, failing on an unfamiliar layout."""
    start = source.index(signature + '\n{')
    end = source.index('\n}', start) + 2
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kernel', type=Path, help='trusted external kernel source directory')
    parser.add_argument('--cc', default='cc', help='C compiler executable')
    args = parser.parse_args()
    source = (args.kernel / 'drivers/hid/hidraw.c').read_text()
    extracted = '\n\n'.join(function(source, signature) for signature in (
        'static int hidraw_open(struct inode *inode, struct file *file)',
        'static void drop_ref(struct hidraw *hidraw, int exists_bit)',
    ))
    with tempfile.TemporaryDirectory(prefix='barracuda-hidraw-probe-') as directory:
        path = Path(directory)
        program = path / 'probe.c'
        program.write_text(STUBS + extracted + SCENARIOS)
        executable = path / 'probe'
        subprocess.run([args.cc, '-std=c11', '-Wall', '-Wextra', '-Werror',
                        '-Wno-unused-parameter', str(program), '-o', str(executable)],
                       check=True)
        subprocess.run([str(executable)], check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
