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
package Session::Processes;

use strict;
use warnings;

sub print_field_headers {
    my ($fields) = @_;

    my @fields = split ',', $fields;

    foreach my $field (@fields) {
        print "$field, ";
    }
}

sub print_fields {
    my ( $fields, $line ) = @_;

    my $i = 1;
    for my $field ( split / /, $fields ) {
        my $val = `echo -n "$line" | awk "{print \$$i}" | tr -d '\n'`;
        print "$val, ";
        $i++;
    }
}

sub print_smap_var {
    my ( $var, $pid ) = @_;

    my $add = $var eq "rss" ? 0.5 : 0;
    print `awk "/^$var/ {i = i + \\\$2 + $add} END {printf \\\"%d\\\",i}" \\
           /proc/$pid/smaps`;
}

# returns a descriptive line of a process
sub get_process_line {
    my ( $processes, $child_pid ) = @_;

    return "$processes->{$child_pid}{'namesmem'} $child_pid";
}

# recursive function to print a process tree
sub print_process_tree {
    my ( $processes_children, $processes, $pid, $indent ) = @_;

    if ( exists $$processes_children{$pid} ) {
        my $child_index = scalar @{ $$processes_children{$pid} };
        foreach my $child_pid ( @{ $$processes_children{$pid} } ) {
            my $process_line = get_process_line $processes, $child_pid;
            print $indent. "$process_line\n";

            my $new_indent = $indent;
            if ( $child_index-- == 1 ) {
                $new_indent =~ s/ \\_/   /g;
            }
            else {
                $new_indent =~ s/ \\_/ | /g;
            }
            $new_indent .= " \\_";

            print_process_tree( $processes_children, $processes, $child_pid,
                $new_indent );
        }
    }
}

# displays the process window
sub process_window {
    my ($cgroup, $logs) = @_;

    # TODO store all fields in logs

    my @fields    = ();
    my @ps_fields = (
        'pid',      'ppid',          'rss',     'pcpu',
        'cutime',   'utime min_flt', 'maj_flt', 'cmin_flt',
        'cmaj_flt', 'size',          'share',   'vsize',
        'cgroup'
    );
    my $ps_fields = join ',', @ps_fields;
    push @fields, @ps_fields;

    my @smem_fields = ( 'pid', 'rss', 'pss', 'swap', 'uss', 'vss', 'name' );
    my $smem_fields = join ' ', @smem_fields;
    for (@smem_fields) {
        $_ .= "smem";
    }
    push @fields, @smem_fields;

    my @smap_fields = (
        'Rss',           'Pss', 'Shared_Clean', 'Shared_Dirty',
        'Private_Clean', 'Private_Dirty'
    );

    my @processes = split '\n', `ps hax -ww -o "$ps_fields" | grep "$cgroup"`;
    my $processes = {};

    my $processes_children = {};
    my $smem               = `sudo smem -H -c "$smem_fields"`;
    foreach my $output (@processes) {
        my @output = split ' ', $output;
        my $pid = $output[0];

        my $smem_pid = `echo "$smem" | /usr/bin/grep "^[ ]*$pid *"`;
        next if ( $? != 0 );

        chomp $smem_pid;

        my @smem = split ' ', $smem_pid;

        shift @smem;
        push @output, @smem;
        $processes->{$pid} = {};
        @{ $processes->{$pid} }{@fields} = (@output);
        my $ppid = $processes->{$pid}{ppid};

        if ( not( grep { $_ == $ppid } %$processes ) ) {
            $ppid = 0;
        }

        if ( not exists $$processes_children{$ppid} ) {
            my @empty = ();
            $$processes_children{$ppid} = \@empty;
        }
        push $$processes_children{$ppid}, $pid;
    }

    print_process_tree $processes_children, $processes, 0, "";
}

1;
