use utf8;
use strict;
use warnings;

package DR::Tarantool::Spaces;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

=head1 NAME

DR::Tarantool::Spaces - spaces container

=head1 SYNOPSIS

    use DR::Tarantool::Spaces;
    my $s = new DR::Tarantool::Spaces({
            1   => {
                name            => 'users',         # space name
                default_type    => 'STR',           # undescribed fields
                fields  => [
                    qw(login password role),
                    {
                        name    => 'counter',
                        type    => 'NUM'
                    },
                    {
                        name    => 'something',
                        type    => 'UTF8STR',
                    }
                ],
                indexes => {
                    0   => 'login',
                    1   => [ qw(login password) ],
                    2   => {
                        name    => 'my_idx',
                        fields  => 'login',
                    },
                    3   => {
                        name    => 'my_idx2',
                        fields  => [ 'counter', 'something' ]
                    }
                }
            },

            0 => {
                ...
            }
    });

    my $f = $s->pack_field('users', 'counter', 10);
    my $f = $s->pack_field('users', 1, 10);             # the same
    my $f = $s->pack_field(1, 1, 10);                   # the same


=head1 METHODS

=head2 new

    my $spaces = DR::Tarantool::Spaces->new( $spaces );

=cut

sub new {
    my ($class, $spaces) = @_;
    croak 'spaces must be a HASHREF' unless 'HASH' eq ref $spaces;
    croak "'spaces' is empty" unless %$spaces;

    my (%spaces, %fast);
    for (keys %$spaces) {
        my $s = new DR::Tarantool::Space($_ => $spaces->{ $_ });
        $spaces{ $s->name } = $s;
        $fast{ $_ } = $s->name;
    }

    return bless {
        spaces  => \%spaces,
        fast    => \%fast,
    } => ref($class) || $class;
}


=head2 space

Returns space object by number or name.

    my $space = $spaces->space('name');
    my $space = $spaces->space(0);

=cut

sub space {
    my ($self, $space) = @_;
    croak 'space name or number is not defined' unless defined $space;
    if ($space =~ /^\d+$/) {
        croak "space '$space' is not defined"
            unless exists $self->{fast}{$space};
        return $self->{spaces}{ $self->{fast}{$space} };
    }
    croak "space '$space' is not defined"
        unless exists $self->{spaces}{$space};
    return $self->{spaces}{$space};
}


=head2 pack_field

packs one field before making database request

    my $field = $spaces->pack_field('space', 'field', $data);

=cut

sub pack_field {
    my ($self, $space, $field, $value) = @_;
    croak q{Usage: $spaces->pack_field('space', 'field', $value)}
        unless @_ == 4;
    return $self->space($space)->pack_field($field => $value);
}


=head2 unpack_field

unpacks one field after extracting data from database

    my $field = $spaces->unpack_field('space', 'field', $data);

=cut

sub unpack_field {
    my ($self, $space, $field, $value) = @_;
    croak q{Usage: $spaces->unpack_field('space', 'field', $value)}
        unless @_ == 4;

    return $self->space($space)->unpack_field($field => $value);
}


=head2 pack_tuple

packs tuple before making database request

    my $t = $spaces->pack_tuple('space', [ 1, 2, 3 ]);

=cut

sub pack_tuple {
    my ($self, $space, $tuple) = @_;
    croak q{Usage: $spaces->pack_tuple('space', $tuple)} unless @_ == 3;
    return $self->space($space)->pack_tuple( $tuple );
}


=head2 unpack_tuple

unpacks tuple after extracting data from database

    my $t = $spaces->unpack_tuple('space', \@fields);

=cut

sub unpack_tuple {
    my ($self, $space, $tuple) = @_;
    croak q{Usage: $spaces->unpack_tuple('space', $tuple)} unless @_ == 3;
    return $self->space($space)->unpack_tuple( $tuple );
}

package DR::Tarantool::Space;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

=head1 SPACES methods

=head2 new

constructor

    use DR::Tarantool::Spaces;
    my $space = DR::Tarantool::Space->new($no, $space);

=cut

sub new {
    my ($class, $no, $space) = @_;
    croak 'space number must conform the regexp qr{^\d+}' unless $no ~~ /^\d+$/;
    croak "'fields' not defined in space hash"
        unless 'ARRAY' eq ref $space->{fields};
    croak "wrong 'indexes' hash"
        if !$space->{indexes} or 'HASH' ne ref $space->{indexes};

    my $name = $space->{name};
    croak 'wrong space name: ' . ($name // 'undef')
        unless $name and $name =~ /^[a-z_]\w*$/i;


    my (@fields, %fast, $default_type);
    $default_type = $space->{default_type} || 'STR';
    croak "wrong 'default_type'"
        unless $default_type =~ /^(?:STR|NUM|NUM64|UTF8STR)$/;

    for (my $no = 0; $no < @{ $space->{fields} }; $no++) {
        my $f = $space->{ fields }[ $no ];

        if (ref $f eq 'HASH') {
            push @fields => {
                name    => $f->{name} || "f$no",
                idx     => $no,
                type    => $f->{type}
            };
        } elsif(ref $f) {
            croak 'wrong field name or description';
        } else {
            push @fields => {
                name    => $f,
                idx     => $no,
                type    => $default_type,
            }
        }

        my $s = $fields[ -1 ];
        croak 'unknown field type: ' . ($s->{type} // 'undef')
            unless $s->{type} and $s->{type} =~ /^(?:STR|NUM|NUM64|UTF8STR)$/;

        croak 'wrong field name: ' . ($s->{name} // 'undef')
            unless $s->{name} and $s->{name} =~ /^[a-z_]\w*$/i;

        croak "Duplicate field name: $s->{name}" if exists $fast{ $s->{name} };
        $fast{ $s->{name} } = $no;
    }

    my %indexes;
    if ($space->{indexes}) {
        for my $no (keys %{ $space->{indexes} }) {
            my $l = $space->{indexes}{ $no };
            croak "wrong index number: $no" unless $no =~ /^\d+$/;

            my ($name, $fields);

            if ('ARRAY' eq ref $l) {
                $name = "i$no";
                $fields = $l;
            } elsif ('HASH' eq ref $l) {
                $name = $l->{name} || "i$no";
                $fields =
                    [ ref($l->{fields}) ? @{ $l->{fields} } : $l->{fields} ];
            } else {
                $name = "i$no";
                $fields = [ $l ];
            }

            croak "wrong index name: $name" unless $name =~ /^[a-z_]\w*$/i;

            for (@$fields) {
                croak "field '$_' is presend in index but isn't in fields"
                    unless exists $fast{ $_ };
            }

            $indexes{ $name } = {
                no      => $no,
                name    => $name,
                fields  => $fields
            };

        }
    }

    bless {
        fields          => \@fields,
        fast            => \%fast,
        name            => $name,
        number          => $no,
        default_type    => $default_type,
        indexes         => \%indexes,
    } => ref($class) || $class;

}


=head2 name

returns space name

=cut

sub name { $_[0]{name} }


=head2 number

returns space number

=cut

sub number { $_[0]{number} }

sub _field {
    my ($self, $field) = @_;

    croak 'field name or number is not defined' unless defined $field;
    if ($field =~ /^\d+$/) {
        return $self->{fields}[ $field ] if $field < @{ $self->{fields} };
        return undef;
    }
    croak "field with name '$field' is not defined in this space"
        unless exists $self->{fast}{$field};
    return $self->{fields}[ $self->{fast}{$field} ];
}


=head2 pack_field

packs field before making database request

=cut

sub pack_field {
    my ($self, $field, $value) = @_;
    croak q{Usage: $space->pack_field('field', $value)}
        unless @_ == 3;

    my $f = $self->_field($field);

    my $type = $f ? $f->{type} : $self->{default_type};

    my $v = $value;
    utf8::encode( $v ) if utf8::is_utf8( $v );
    return $v if $type eq 'STR' or $type eq 'UTF8STR';
    return pack 'L<' => $v if $type eq 'NUM';
    return pack 'Q<' => $v if $type eq 'NUM64';
    croak 'Unknown field type:' . $type;
}


=head2 unpack_field

unpacks field after extracting data from database

=cut

sub unpack_field {
    my ($self, $field, $value) = @_;
    croak q{Usage: $space->pack_field('field', $value)}
        unless @_ == 3;

    my $f = $self->_field($field);

    my $type = $f ? $f->{type} : $self->{default_type};

    my $v = $value;
    utf8::encode( $v ) if utf8::is_utf8( $v );
    $v = unpack 'L<' => $v  if $type eq 'NUM';
    $v = unpack 'Q<' => $v  if $type eq 'NUM64';
    utf8::decode( $v )      if $type eq 'UTF8STR';
    return $v;
}


=head2 pack_tuple

packs tuple before making database request

=cut

sub pack_tuple {
    my ($self, $tuple) = @_;
    croak 'tuple must be ARRAYREF' unless 'ARRAY' eq ref $tuple;
    my @res;
    for (my $i = 0; $i < @$tuple; $i++) {
        push @res => $self->pack_field($i, $tuple->[ $i ]);
    }
    return \@res;
}


=head2 unpack_tuple

unpacks tuple after extracting data from database

=cut

sub unpack_tuple {
    my ($self, $tuple) = @_;
    croak 'tuple must be ARRAYREF' unless 'ARRAY' eq ref $tuple;
    my @res;
    for (my $i = 0; $i < @$tuple; $i++) {
        push @res => $self->unpack_field($i, $tuple->[ $i ]);
    }
    return \@res;
}


sub _index {
    my ($self, $index) = @_;
    if ($index =~ /^\d+$/) {
        for (values %{ $self->{indexes} }) {
            return $_ if $_->{no} == $index;
        }
        croak "index $index is not defined";
    }

    return $self->{indexes}{$index} if exists $self->{indexes}{$index};
    croak "index `$index' is not defined";
}

sub pack_keys {
    my ($self, $keys, $idx) = @_;

    $idx = $self->_index($idx);
    my $ksize = @{ $idx->{fields} };

    if ($ksize == 1) {
        $keys = [ $keys ] unless ref $keys;
        unless('ARRAY' eq ref $keys->[ 0 ]) {
            $_ = [ $_ ] for @$keys;
        }
    } else {
        croak "key must have $ksize elements" unless 'ARRAY' eq ref $keys;
        $keys = [ $keys ] unless 'ARRAY' eq ref $keys->[ 0 ];
    }

    my @res;
    for my $k (@$keys) {
        croak "key must have $ksize elements" unless $ksize == @$k;
        my @packed;
        for (my $i = 0; $i < @$k; $i++) {
            my $f = $self->_field($idx->{fields}[$i]);
            push @packed => $self->pack_field($f->{name}, $k->[$i])
        }
        push @res => \@packed;
    }
    return \@res;
}

sub pack_key {
    my ($self, $key) = @_;

    croak 'wrong key format'
        if 'ARRAY' eq ref $key and 'ARRAY' eq ref $key->[0];

    my $t = $self->pack_keys($key, 0);
    return $t->[0];
}

sub pack_operation {
    my ($self, $op) = @_;
    croak 'wrong operation' unless 'ARRAY' eq ref $op and @$op > 1;

    my $fno = $op->[0];
    my $opname = $op->[1];

    my $f = $self->_field($fno);

    if ($opname eq 'delete') {
        croak 'wrong operation' unless @$op == 2;
        return [ $f->{idx} => $opname ];
    }

    if ($opname =~ /^(?:set|insert|add|and|or|xor)$/) {
        croak 'wrong operation' unless @$op == 3;
        return [ $f->{idx} => $opname, $self->pack_field($fno, $op->[2]) ];
    }

    if ($opname eq 'substr') {
        croak 'wrong operation11' unless @$op >= 4;
        croak 'wrong offset in substr operation' unless $op->[2] =~ /^\d+$/;
        croak 'wrong length in substr operation' unless $op->[3] =~ /^\d+$/;
        return [ $f->{idx}, $opname, $op->[2], $op->[3], $op->[4] ];
    }
    croak "unknown operation: $opname";
}

sub pack_operations {
    my ($self, $ops) = @_;

    croak 'wrong operation' unless 'ARRAY' eq ref $ops and @$ops >= 1;
    $ops = [ $ops ] unless 'ARRAY' eq ref $ops->[ 0 ];

    my @res;
    push @res => $self->pack_operation( $_ ) for @$ops;
    return \@res;
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
