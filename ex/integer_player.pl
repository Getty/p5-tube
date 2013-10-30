{
  package MyPlayer;

  use Moo;

  use POE;
  use DDP;

  use ZMQ::Constants qw(
    ZMQ_ROUTER
    ZMQ_IDENTITY
    ZMQ_REQ
    ZMQ_SNDMORE
  );

  use POSIX qw( floor );
  use Time::HiRes qw( time gettimeofday tv_interval );
  
  use Data::MessagePack;

  with 'POEx::ZMQ3::Role::Emitter';

  has port => (
    is => 'ro',
    lazy => 1,
    default => sub { 12345 },
  );
   
  has host => (
    is => 'ro',
    lazy => 1,
    default => sub { 'localhost' },
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
    is => 'rw',
  );

  has start_tick => (
    is => 'rw',
    lazy => 1,
    default => sub { 0 },
  );

  sub current_tick {
    my ( $self ) = @_;
    my $diff = time - $self->start_time;
    return floor( $diff / $self->tickdelay ) + $self->start_tick;
  }

  has connect_on => (
    is => 'ro',
    default => sub { 'tcp://'.$_[0]->host.':'.$_[0]->port },
  );

  sub build_defined_states {
    my ($self) = @_;
    [ $self => [qw/
      emitter_started
      zmqsock_bind_added
      zmqsock_connect_added
      zmqsock_recv
      zmqsock_multipart_recv
      zmqsock_created
      zmqsock_closing
      tick
      need_tick
    /], ],
  }

  sub BUILD {
    my ( $self ) = @_;
    $self->start;
  }

  sub zmqsock_bind_added {
    print "zmqsock_bind_added";
    p(@_[ARG0..ARG1]);
  }

  sub zmqsock_connect_added {
    print "zmqsock_connect_added";
    p(@_[ARG0..ARG1]);
  }

  sub zmqsock_recv {
    if ($_[0]->start_tick) {
      print "diff ".( $_[0]->current_tick - Data::MessagePack->unpack($_[ARG1]) )."\n";
    } else {
      print "got tick ".$_[ARG1]."\n";
      $_[0]->start_tick(Data::MessagePack->unpack($_[ARG1]));
      $_[0]->start_time(time);
      $_[0]->tick;
    }
  }

  sub zmqsock_multipart_recv {
    print "zmqsock_multipart_recv";
    p(@_[ARG0..ARG1]);
  }

  sub zmqsock_created {
    print "zmqsock_created";
    p(@_[ARG0..ARG1]);
  }

  sub zmqsock_closing {
    print "zmqsock_closing";
    p(@_[ARG0..ARG1]);
  }

  sub start {
    my ( $self ) = @_;
    $self->zmq->start;
    $self->zmq->create( $self->alias, ZMQ_REQ );
    $self->zmq->set_zmq_sockopt( $self->alias, ZMQ_IDENTITY, int(rand(100000)) );
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
    $self->add_connect( $self->alias, $self->connect_on );
    print "Connecting to ".$self->connect_on."\n";
    $poe_kernel->delay( need_tick => 1 );
  }

  sub need_tick {
    return if $_[0]->start_tick;
    print "need tick!\n";
    
    $_[0]->zmq->write( $_[0]->alias, Data::MessagePack->pack('needtick') );
    
    $poe_kernel->delay( need_tick => 1 );
  }

  sub tick {
    my ( $self ) = @_;
    
    $self->zmq->write( $self->alias, Data::MessagePack->pack($self->current_tick) );
    
    $poe_kernel->delay( tick => $self->tickdelay );
  }

  sub run { $poe_kernel->run }
}

# tick => sub {
#   $z->write('player',rand());
#   $poe_kernel->delay( tick => 1 );
# },

$|=1;
MyPlayer->new->run;
