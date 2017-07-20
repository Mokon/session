#!/usr/bin/perl
# The MIT License (MIT)
#
# Copyright (c) 2016 David Bond
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
package Session::Session;

use strict;
use warnings;

use Cwd;
use Data::Dumper;
use File::Path;
use Getopt::Long;
use Sysadm::Install;

use Session::Processes;

sub tmux {
    my ( $stdout, $stderr, $rc ) = Sysadm::Install::tap 'tmux', @_;
    return $rc;
}

my $window = undef;
my $mode   = undef;
my $logs   = undef;

GetOptions(
    'window=s' => \$window,
    'mode=s'   => \$mode,
    'logs=s'   => \$logs
) or die 'opts bad';

my $install_dir = File::Basename::dirname( Cwd::abs_path($0) );
my $cfg_fn      = '/session.cfg';

# These can be overridden in the config file.
my $session = 'system';
my $cgroup  = 'system';
my @windows = ();

if ( defined $logs ) {
    $logs .= "/" . time;
    File::Path::make_path($logs);
}

if (
    open CONF,
    $cfg_fn or open CONF,
    "$install_dir/$cfg_fn" or open CONF,
    "$ENV{HOME}/$cfg_fn"
  )
{
    local $/ = undef;
    eval <CONF>;
    close CONF;
}

sub create_cmd {
    my ( $window ) = @_;

    my $cmd = $window->{cmd};
    
    if (defined($window->{sleep})) {
      $cmd = "sleep ".$window->{sleep}."; ".$cmd;
    }
    
    if (defined($window->{watch})) {
      $cmd = "watch -n ".$window->{watch}." ".$cmd;
    }

    if (defined($window->{cd})) {
      $cmd = "cd ".$window->{cd}."; ".$cmd;
    }

    #`echo "$cmd" >> ~/cmd.log`

    return $cmd;
}

if ( not defined($window) or $window eq 'main' ) {
    if ( ( tmux 'has-session', '-t', $session ) eq 0 ) {
        tmux 'kill-session', '-t', $session;
    }
    my $group_index = 1;
    for my $group (@windows) {
        my $window_index = 1;
        for my $window (@$group) {
            if ( not defined( $window->{mode} ) or $window->{mode} eq $mode ) {
                my $cmd = create_cmd $window;
                if ( $window_index eq 1 and $group_index eq 1 ) {
                    tmux 'new-session', '-d', '-s', $session, '-n',
                      $window->{name}, $cmd;
                }
                elsif ( $window_index eq 1 ) {
                    tmux 'new-window', '-t', "$session:$group_index", '-n',
                      $window->{name}, $cmd;
                }
                else {
                    tmux 'split-window', '-p', $window->{perc}, '-h',
                      $window->{cmd};
                }
                $window_index++;
            }
        }
        $group_index++;
    }

    tmux 'select-window',  '-t', "$session:1";
    tmux 'attach-session', '-t', $session;
}
elsif ( $window eq 'processes' ) {
    Session::Processes::process_window $cgroup, $logs;
}
else {
    die 'unknown window';
}
