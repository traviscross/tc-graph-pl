#!/usr/bin/perl
#-------------------------------------------------------------------
# File:        tc-graph.pl
# Description: Use tc output to create GraphViz dot file.
#              Based on Stef Coene's 'show.pl' from www.docum.org,
#              you can visualize your qdisc/class/filter structure
#              if you feed the GraphViz program 'dot' with the output.
#              I'm no perl programmer, so it may be a little crappy.
# Author:      Andreas Klauer (Andreas.Klauer@metamorpher.de)
# Date:        2004-05-12
# Version:     v0.13
#

if ($#ARGV + 1 < 1 ) {
    print "Usage: $0 <interface>\n";
    exit(1);
}

$BIN_TC="/sbin/tc";
$DEV=$ARGV[0];
$USE_CLUSTER=0;

%parent_hash;    # $child => $parent
%child_hash;     # $parent  => @child_hash
%info_hash;      # $classid => $info

# FUNCTION:        parse_qdisc
# DESCRIPTION:
#   This subroutine parses the qdisc output of the tc command.
#   It puts stuff into the child_hash and info hashes.
# SEE ALSO:
sub parse_qdisc
{
    my @qdisc=`$BIN_TC -d qdisc show dev $DEV`;

    foreach $line (@qdisc)
    {
        chomp $line;

        @words = split(/ +/, $line);

        $name = $words[1]; # name of qdisc
        $id   = $words[2]; # handle/id of qdisc

        # Throw the first three elements away. (qdisc name handle)
        shift(@words);
        shift(@words);
        shift(@words);

#        print "\n\n!! AAA KEY \"$id\"\n\n";

        # Put into hashes.
        push(@{$child_hash{$id}}, 0);
        pop(@{$child_hash{$id}});
        $info_hash{$id} = "qdisc\n$name";

    # The remaining words are "parameter value parameter value ..."
    # Special case is "priomap" parameter, which hase more than one value.
    # At the moment, we avoid this problem by doing a hack:
    #    Parameter names never start with numbers -
    #    but Values always start with numbers.
    # Seems to work. Even if it doesn't, the info will still show up,
    # only formatting will be ugly.

        # Add more info.
        foreach $word (@words)
        {
            # Bad hack:
            if($word =~ /^[^0-9]/)
            {
                # Anything that doesn't start with a number is a descriptor.
                $info_hash{$id} .= "\n$word";
            }

            else
            {
                # Anything else is a value.
                $info_hash{$id} .= " $word";
            }
        }
    }
}

# FUNCTION:        parse_class
# DESCRIPTION:
#   This subroutine parses the class output of the tc command.
#   It prints the respictive dot node creation commands.
#   It also creates the connections between the nodes.
# SEE ALSO:
sub parse_class
{
    my @class=`$BIN_TC -d class show dev $DEV`;

    foreach $line (@class)
    {
        chomp $line;

        @words = split(/ +/, $line);

        $name = $words[1]; # Name of class (e.g. htb, cbq, ...)
        $id   = $words[2]; # Handle of class (X:Y)

        # Throw the first three elements away. (class name handle)
        shift(@words);
        shift(@words);
        shift(@words);

        # Create entry even if empty for this class:
#        print "\n\n!! KEY \"$id\"\n\n";
        push(@{$child_hash{$id}}, 0);
        pop(@{$child_hash{$id}});

        if($words[0] eq "root")
        {
            # Root class. No parent class, but parent qdisc.
            # We get the parent qdisc handle by removing Y from X:Y.
            $parent_id = $id;
            $parent_id =~ s/:.*/:/;

            # Tell qdisc that this is its child_hash.
            $parent_hash{$id} = $parent_id;
            push(@{$child_hash{$parent_id}}, $id);

            # Add info.
            $info_hash{$id} = "root\n$name";

            # Kill "root"
            shift(@words);
        }

        elsif($words[0] eq "parent")
        {
            # Child class with parent class.
            $parent_id = $words[1];

            # Tell parent that it has a child_hash.
            $parent_hash{$id} = $parent_id;
            push(@{$child_hash{$parent_id}}, $id);
            $info_hash{$id} = "class\n$name";

            # Kill "parent handle"
            shift(@words);
            shift(@words);
        }

        if($words[0] eq "leaf")
        {
            $leaf = $words[1];

            # Yo cool we got a leaf here.
            $parent_hash{$leaf} = $id;
            push(@{$child_hash{$id}}, $leaf);

            # Tell that qdisc that it's a leaf.
            $info_hash{$leaf} = "leaf\n$info_hash{$leaf}";

            # Kill "leaf X:"
            shift(@words);
            shift(@words);
        }

    # The remaining words are "parameter value parameter value ..."
    # Special case is "priomap" parameter, which hase more than one value.
    # At the moment, we avoid this problem by doing a hack:
    #    Parameter names never start with numbers -
    #    but Values always start with numbers.
    # Seems to work. Even if it doesn't, the info will still show up,
    # only formatting will be ugly.

        # Add more info.
        foreach $word (@words)
        {
            # Bad hack:
            if($word =~ /^[^0-9]/)
            {
                # Anything that doesn't start with a number is a descriptor.
                $info_hash{$id} .= "\n$word";
            }

            else
            {
                # Anything else is a value.
                $info_hash{$id} .= " $word";
            }
        }
    }
}

sub spaceprint
{
    $count = shift;
    $text = shift;

    while($count > 0)
    {
        print "    ";
        $count = $count - 1;
    }

    print $text;
}

sub cluster
{
    my $handle = shift;
    my $level = shift;

    my $name = $handle;
    $name =~ s/:/_/g;

    spaceprint($level, "subgraph cluster_$name\n");
    spaceprint($level, "{\n");
    spaceprint($level, "    \"$handle\";\n\n");

    foreach $child (@{$child_hash{$handle}})
    {
        cluster($child, $level+1);
    }

    spaceprint($level, "}\n\n");
}

sub print_structure
{
    if($USE_CLUSTER == 1)
    {
        # Create all child_hash nodes in same-rank clusters:
        foreach $parent (sort keys %child_hash)
        {
            # Create clusters from top.
            if($parent_hash{$parent} == 0)
            {
                cluster($parent, 1);
            }
        }
    }

    # Add info for all nodes:
    foreach $id (sort keys %info_hash)
    {
        @{$info_hash{$id}} = split("\n", $info_hash{$id});
        @words = @{$info_hash{$id}};

        if($words[0] eq "qdisc")
        {
            # Shift "qdisc"
            shift(@words);

            # Set node settings:
            $node = "shape=polygon,sides=64,peripheries=3,fillcolor=\"#AAAAFF\"";
        }

        elsif($words[0] eq "leaf")
        {
            # Shift "leaf qdisc"
            shift(@words);
            shift(@words);

            # Set node settings:
            $node = "shape=polygon,sides=64,peripheries=2,fillcolor=\"#CCCCFF\"";
        }

        elsif($words[0] eq "root")
        {
            # Shift "root"
            shift(@words);

            # Set node settings:
            $node = "shape=polygon,sides=64,peripheries=3,fillcolor=\"#AAFFAA\"";
        }

        elsif($words[0] eq "class")
        {
            # Shift "class"
            shift(@words);

            # Set node settings:
            $node = "shape=polygon,sides=64,peripheries=2,fillcolor=\"#CCFFCC\"";
        }

        print "    \"$id\" [$node,label=\"$id\\n";

        # Add info.
        foreach $line (@words)
        {
            $line =~ s/\n/ /g;
            $line =~ s/ +/ /g;
            $line =~ s/^ +//;
            $line =~ s/ *$/\\n/;
            print $line;
        }

        print "\"];\n";
    }

    print "\n";

    # Create edges.
    foreach $parent (sort keys %child_hash)
    {
        foreach $child (sort @{$child_hash{$parent}})
        {
            @words = @{$info_hash{$child}};

            # "qdisc" can't happen, because those are called "leafs"

            if($words[0] eq "leaf")
            {
                $edge = "style=bold,color=green";
            }

            elsif($words[0] eq "root")
            {
                $edge = "style=bold,color=red";
            }

            elsif($words[0] eq "class")
            {
                $edge = "color=black";
            }

            print "    \"$parent\" -> \"$child\" [$edge];\n";
        }
    }
}

# FUNCTION:        parse_filter
# DESCRIPTION:
#   This function parses & prints the filter output of the tc command.
#
#   FIXME:  tc produces crazy output for filters, so it's hardly supported.
#   FIXME:: You'd have to put a lot of effort into this to support *all* modes.
#
# SEE ALSO:
sub print_filter
{
    my @filter;

    foreach $parent (sort keys %child_hash)
    {
        @filter=`$BIN_TC -d filter show dev $DEV parent $parent`;

        foreach $line (@filter)
        {
            chomp $line;

            @words = split(/ +/, $line);

            # Get class in a weird way
            if(@words[-2] eq "classid")
            {
                $class = @words[-1];

                print "    \"$parent\" -> \"$class\" ";

                # Kill stuff.
                shift(@words);
                shift(@words);
                pop(@words);
                pop(@words);

                # Coloring
                print "[color=blue";

                # Label if it's a handle.
                if(@words[-2] eq "handle")
                {
                    print ",labelfontcolor=blue,label=\"(";
                    print hex @words[-1];
                    print ")\"";
                }

                print "];\n";
            }
        }
    }
}

# --- Main: ---

# Yes, this is perl for stupid people (like me).

print "digraph QOS {\n";
#print "   ratio=compress\n";
print "   node [style=filled,shape=box]\n";
print "   ratio=fill;\n";
print "   mclimit=200.0;\n";
print "   nslimit=200.0;\n";

parse_qdisc;
parse_class;
print_structure;
print_filter;

print "\n}\n";

# --- End of file. ---
