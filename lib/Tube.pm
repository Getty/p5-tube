package Tube;

use Moo;

use POE;
use DDP;
use ZMQ::Constants qw(
  ZMQ_ROUTER
  ZMQ_IDENTITY
  ZMQ_SNDMORE
);

use POSIX qw( floor );
use Time::HiRes qw( time gettimeofday tv_interval );

with 'POEx::ZMQ3::Role::Emitter';

has port => (
  is => 'ro',
  lazy => 1,
  default => sub { 12345 },
);
 
has host => (
  is => 'ro',
  lazy => 1,
  default => sub { '*' },
);

has players => (
  is => 'ro',
  lazy => 1,
  default => sub {{}},
);

has tickrate => (
  is => 'ro',
  lazy => 1,
  default => sub { 100 },
);

has tickdelay => (
  is => 'ro',
  lazy => 1,
  default => sub { 1 / $_[0]->tickrate },
);

has start_time => (
  is => 'ro',
  lazy => 1,
  default => sub { time },
);

sub current_tick {
  my ( $self ) = @_;
  my $diff = time - $self->start_time;
  return floor( $diff / $self->tickdelay );
}

has listen_on => (
  is => 'ro',
  default => sub { 'tcp://'.$_[0]->host.':'.$_[0]->port },
);

sub build_defined_states {
  my ($self) = @_;
  [ $self => [qw/
    emitter_started
    zmqsock_bind_added
    zmqsock_multipart_recv
    zmqsock_created
    zmqsock_closing
    tick
  /], ],
}

sub BUILD {
  my ( $self ) = @_;
  $self->start;
  $self->start_time;
}

sub zmqsock_bind_added { print "Listening to ".$_[ARG1]."\n" }
sub zmqsock_created { print "Created socket type ".$_[ARG1]."\n" }
sub zmqsock_closing { print "[".$_[ARG0]."] closing\n" }

sub zmqsock_multipart_recv {
  my ( $from, $envelope, $data ) = @{$_[ARG1]};
  if ($data eq 'needtick') {
    print "[".sprintf("%10s",$from)."] need tick\n";
  } else {
    my $diff = $_[0]->current_tick - $data;
    print "[".sprintf("%10s",$from)."] ".sprintf("%10d",$data)." ".sprintf("%10d",$diff)."\n" if $diff;
  }
  $_[0]->zmq->write( $_[0]->alias, $from, ZMQ_SNDMORE );
  $_[0]->zmq->write( $_[0]->alias, '', ZMQ_SNDMORE );
  $_[0]->zmq->write( $_[0]->alias, $_[0]->current_tick );
}

sub start {
  my ( $self ) = @_;
  $self->zmq->start;
  $self->zmq->create( $self->alias, ZMQ_ROUTER );
  $self->zmq->set_zmq_sockopt( $self->alias, ZMQ_IDENTITY, 'SERVER' );
  $self->_start_emitter;
}

sub stop {
  my ( $self ) = @_;
  $self->zmq->stop;
  $self->_shutdown_emitter;
}

sub emitter_started {
  my ( $self ) = @_;
  $poe_kernel->call( $self->zmq->session_id, subscribe => 'all' );
  $self->add_bind( $self->alias, $self->listen_on );
  $poe_kernel->delay( tick => 1 );
}

sub tick {
  my ( $self ) = @_;
  print "tick ".$self->current_tick."\n";
  $poe_kernel->delay( tick => $self->tickdelay );
}

sub run { $poe_kernel->run }

1;
