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

    if (defined $space) {
        croak 'wrong space' unless blessed $space;
    }

    croak 'tuple must be ARRAYREF [of ARRAYREF]' unless 'ARRAY' eq ref $tuple;
    croak "tuple can't be empty" unless @$tuple;
    if ('ARRAY' eq ref $tuple->[0]) {
        my $self = $class->new( $tuple->[0], $space );

        for (my $i = 1; $i < @$tuple; $i++) {
            $self->next( $tuple->[1] );
        }
        return $self;
    }

    my $self = bless {
        tuple   => [ @$tuple ],
        space   => $space,
    } => ref($class) || $class;
#     weaken $self->{space} if defined $self->{space};
    return $self;
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
    return $self->{tuple} unless @_ > 1;
    croak 'wrong field_no: ' . ($fno // 'undef')
        unless defined $fno and $fno =~ /^\d+$/;
    return undef if $fno > $#{ $self->{tuple} };
    return $self->{tuple}[ $fno ];
}


=head2 next

Appends or returns the following tuple.

    my $next_tuple = $tuple->next;

=cut

sub next :method {

    my ($self, $tuple) = @_;
    return $self->{tail} if @_ == 1;

    $tuple = $self->new($tuple, $self->{space});
    my $o = $self;
    $o = $o->{tail} while defined $o->{tail};
    $o->{tail} = $tuple;
    $tuple;
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

=item method (optional, default: B<new>)

if 'package' and 'method' are present, $iterator->L<next> method will
construct objects using C<< $package->$method( $next_tuple ) >>

=back

=cut

sub iter :method {
    my ($self, $class, $method) = @_;
    return DR::Tarantool::Tuple::Iterator->new( $self, $class, $method );
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

package DR::Tarantool::Tuple::Iterator;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;
use Scalar::Util 'weaken', 'blessed';

=head1 tuple iterators

=head2 new

    my $iter = DR::Tarantool::Tuple::Iterator->new( $tuple );

    my $iter = $tuple->iter;    # the same

=head3 Arguments

=over

=item tuple

=item package (optional)

=item method (optional, default: new)


if 'package' and 'method' are present, L<next> method will construct
objects using C<< $package->$method( $next_tuple ) >>

=back

=cut

sub new {
    my ($class, $t, $iclass, $imethod) = @_;

    if ($iclass) {
        $imethod ||= 'new';
        croak "Can't locate method '$imethod' via package '$iclass'"
            unless $iclass->can($imethod);
    }
    return bless {
        head => $t,
        class   => $iclass,
        method  => $imethod
    } => ref($class) || $class;
}


=head2 count

Returns count of tuples in the iterator.

    my $count = $iter->count;

=cut

sub count {
    my ($self) = @_;
    unless (exists $self->{count}) {
        my $o = $self->{head};
        $self->{count} = 0;
        last unless $o;

        $self->{count}++;

        while($o->{tail}) {
            $o = $o->{tail};
            $self->{count}++;
        }
    }
    $self->{count};
}


=head2 reset

Resets iterator (see L<next> method).

    $iter->reset;

=cut

sub reset {
    my ($self) = @_;
    delete $self->{cur};
}


=head2 next

Returns next element from the iterator.

    my $iter = $tuple->iter;

    while(my $tuple = $iter->next) {
        ...
    }

=cut

sub next :method {
    my ($self) = @_;
    if (defined $self->{cur}) {
        $self->{cur} = $self->{cur}{tail};
    } else {
        $self->{cur} = $self->{head}
    }

    return undef unless defined $self->{cur};
    weaken $self->{cur};


    if ($self->{class}) {
        my ($c, $m) = ($self->{class}, $self->{method});
        $m ||= 'new';
        return $c->$m( $self->{cur} );
    }
    return $self->{cur};

}

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
