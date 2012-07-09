use utf8;
use strict;
use warnings;

=head1 NAME

DR::Tarantool::Tuple - tuple container for L<DR::Tarantool>

=head1 SYNOPSIS

    my $tuple = new DR::Tarantool::Tuple([ 1, 2, 3]);
    my $tuple = new DR::Tarantool::Tuple([ 1, 2, 3], $space);
    my $tuple = unpack DR::Tarantool::Tuple([ 1, 2, 3], $space);


    $tuple->next( $other_tuple );

    $f = $tuple->raw(0);

    $f = $tuple->name_field;


=head1 DESCRIPTION

Tuple contains normalized (unpacked) fields. You can access the fields
by their indexes (see L<raw> function) or by their names (if they are
described in space).

Each tuple can contain references to L<next> tuple and L<iter>ator.
So If You extract more than one tuple, You can access them.

=head1 METHODS

=cut

package DR::Tarantool::Tuple;
use DR::Tarantool::Iterator;
use Scalar::Util 'weaken', 'blessed';
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;


=head2 new

Constructor.

    my $t = DR::Tarantool::Tuple->new([1, 2, 3]);
    my $t = DR::Tarantool::Tuple->new([1, 2, 3], $space);

=cut

sub new :method {
    my ($class, $tuple, $space) = @_;

    $class = ref $class if ref $class;

    croak 'wrong space' if defined $space and !blessed $space;

    croak 'tuple must be ARRAYREF [of ARRAYREF]' unless 'ARRAY' eq ref $tuple;
    croak "tuple can't be empty" unless @$tuple;


    $tuple = [ $tuple ] unless 'ARRAY' eq ref $tuple->[0];

    my $iterator = DR::Tarantool::Iterator->new($tuple);

    return bless {
        idx         => 0,
        iterator    => $iterator,
        space       => $space
    };
}


=head2 unpack

Constructor.

    my $t = DR::Tarantool::Tuple->unpack([1, 2, 3], $space);

=cut

sub unpack :method {
    my ($class, $tuple, $space) = @_;
    croak 'wrong space' unless blessed $space;
    return undef unless defined $tuple;
    croak 'tuple must be ARRAYREF [of ARRAYREF]' unless 'ARRAY' eq ref $tuple;
    return undef unless @$tuple;

    if ('ARRAY' eq ref $tuple->[0]) {
        my @tu;

        push @tu => $space->unpack_tuple($_) for @$tuple;
        return $class->new(\@tu, $space);
    }

    return $class->new($space->unpack_tuple($tuple), $space);
}


=head2 raw

Returns raw data from tuple.

    my $array = $tuple->raw;

    my $field = $tuple->raw(0);

=cut

sub raw :method {
    my ($self, $fno) = @_;

    my $item = $self->{iterator}->item( $self->{idx} );
    return $item unless defined $fno;

    croak 'wrong field number' unless $fno =~ /^-?\d+$/;



    return undef if $fno < -@$item;
    return undef if $fno >= @$item;
    return $item->[ $fno ];
}


=head2 next

Appends or returns the following tuple.

    my $next_tuple = $tuple->next;

=cut

sub next :method {

    my ($self, $tuple) = @_;

    my $iterator = $self->{iterator};
    my $idx = $self->{idx} + 1;

    # if tuple is exists next works like 'iterator->push'
    if ('ARRAY' eq ref $tuple) {
        $iterator->push( $tuple );
        $idx = $iterator->count - 1;
    }

    return undef unless $idx < $iterator->count;

    my $next = bless {
        idx         => $idx,
        iterator    => $iterator,
        space       => $self->{space},
    } => ref($self);

    return $next;
}




=head2 iter

Returns iterator linked with the tuple.


    my $iterator = $tuple->iter;

    my $iterator = $tuple->iter('MyTupleClass', 'new');

    while(my $t = $iterator->next) {
        # the first value of $t and $tuple are the same
        ...
    }

=head3 Arguments

=over

=item package (optional)

=item method (optional)

if 'package' and 'method' are present, $iterator->L<next> method will
construct objects using C<< $package->$method( $next_tuple ) >>

if 'method' is not present and 'package' is present, iterator will
bless raw array into 'package'

=back

=cut

sub iter :method {
    my ($self, $class, $method) = @_;

    my $iterator = $self->{iterator};

    if ($class) {
        return $self->{iterator}->clone(
            item_class =>
            [
                $class,
                sub {
                    my ($c, $item, $idx) = @_;

                    if ($method) {
                        my $bitem = bless {
                            idx => $idx,
                            iterator => $iterator,
                            space => $self->{space}
                        } => ref($self);


                        return $c->$method( $bitem );
                    }
                    return bless [ @$item ] => ref($c) || $c;
                }
            ]
        );
    }

    return $self->{iterator}->clone(
        item_class =>
        [
            ref($self),
            sub {
                my ($c, $item, $idx) = @_;

                my $bitem = bless {
                    idx => $idx,
                    iterator => $iterator,
                    space => $self->{space}
                } => ref($self);

                return $bitem;
            }
        ]
    );
}


=head2 AUTOLOAD

Each tuple autoloads fields by their names that defined in space.

    my $name = $tuple->password; # space contains field with name 'password'
    my $name = $tuple->login;
    ...

=cut

sub AUTOLOAD :method {
    our $AUTOLOAD;
    my ($foo) = $AUTOLOAD =~ /.*::(.*)$/;
    return if $foo eq 'DESTROY';

    my ($self) = @_;
    croak "Can't find field '$foo' in the tuple" unless $self->{space};
    return $self->raw( $self->{space}->_field( $foo )->{idx} );
}

sub DESTROY {  }


=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>
 Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

 This program is free software, you can redistribute it and/or
 modify it under the terms of the Artistic License.

=head1 VCS

The project is placed git repo on github:
L<https://github.com/unera/dr-tarantool/>.

=cut

1;
