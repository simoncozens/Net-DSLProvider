package Net::DSLProvider::Cerberus::soap;
# Generated by SOAP::Lite (v0.710.10) for Perl -- soaplite.com
# Copyright (C) 2000-2006 Paul Kulchenko, Byrne Reese
# -- generated at [Thu Dec 31 13:59:59 2009]
# -- generated from http://nc.cerberusnetworks.co.uk/websvcmgr.php?wsdl&service=dsl
my %methods = (
Wsfinddslline => {
    endpoint => 'http://nc.cerberusnetworks.co.uk/websvcmgr.php',
    soapaction => '',
    namespace => 'http://nc.cerberusnetworks.co.uk',
    parameters => [
      SOAP::Data->new(name => 'CLI', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ClientID', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end Wsfinddslline
Wssubmitorder => {
    endpoint => 'http://nc.cerberusnetworks.co.uk/websvcmgr.php',
    soapaction => '',
    namespace => 'http://nc.cerberusnetworks.co.uk',
    parameters => [
      SOAP::Data->new(name => 'DSLNumber', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ClientOrderRef', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserFirstName', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserLastName', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserCompany', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserAddress1', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserCity', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserPostcode', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserSex', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'UserEmail', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'OrderType', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'PreviousProvider', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'MigrationCode', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'InstallationPID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ServiceRentalPID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'IPOptionPID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'MaintenancePID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'AddServicesPID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'DeliveryPref', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ContractLength', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'AddressSpaceUsage', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'DevicesConnected', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'FlagSkipLineCheck', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end Wssubmitorder
Wsupdateprofile => {
    endpoint => 'http://nc.cerberusnetworks.co.uk/websvcmgr.php',
    soapaction => '',
    namespace => 'http://nc.cerberusnetworks.co.uk',
    parameters => [
      SOAP::Data->new(name => 'CLI', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ClientID', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'INPCode', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'SNRCode', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end Wsupdateprofile
Wsdslgetstats => {
    endpoint => 'http://nc.cerberusnetworks.co.uk/websvcmgr.php',
    soapaction => '',
    namespace => 'http://nc.cerberusnetworks.co.uk',
    parameters => [
      SOAP::Data->new(name => 'CLI', type => 'xsd:string', attr => {}),
      SOAP::Data->new(name => 'ClientID', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end Wsdslgetstats
); # end my %methods

use SOAP::Lite;
use Exporter;
use Carp ();

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

sub _call {
    my ($self, $method) = (shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};
    $self->proxy($method{endpoint} || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;
    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        if (@templates) {
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            my $method = 'as_'.$typename;
            # TODO - if can('as_'.$typename) {...}
            my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
            push(@parameters, $template->value($result->[2]));
        }
        else {
            push(@parameters, $param);
        }
    }
    $self->endpoint($method{endpoint})
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
  $self->serializer->register_ns("http://nc.cerberusnetworks.co.uk/NetCONNECT","db1");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/soap/","soap");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/http","http");
  $self->serializer->register_ns("http://nc.cerberusnetworks.co.uk","tns");
  $self->serializer->register_ns("http://www.w3.org/2001/XMLSchema","xsd");
    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
    }
}
no strict 'refs';
for my $method (@EXPORT_OK) {
    my %method = %{$methods{$method}};
    *$method = sub {
        my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
            ? ref $_[0]
                ? shift # OBJECT
                # CLASS, either get self or create new and assign to self
                : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
            # function call, either get self or create new and assign to self
            : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
        $self->_call($method, @_);
    }
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;
