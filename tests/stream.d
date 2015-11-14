module tests.stream;

import unit_threaded;
import mqttd.stream;
import mqttd.message;
import mqttd.server;


class TestMqttConnection {
    mixin MqttConnection;

    alias Payload = ubyte[];

    void newMessage(in string topic, in ubyte[] payload) {
        import std.stdio;

        writeln("newMessage with payload ", payload);
        payloads ~= payload;
    }

    void write(in ubyte[] bytes) {
    }

    void disconnect() {  }

    const(Payload)[] payloads;

    static assert(isMqttConnection!TestMqttConnection);
}


@HiddenTest
void testMqttInTwoPackets() {
    auto server = new CMqttServer!TestMqttConnection();
    auto connection = new TestMqttConnection;
    auto stream = MqttStream(128);

    ubyte[] bytes1 = [ 0x3c, 0x0f, //fixed header
                       0x00, 0x03, 't', 'o', 'p', //topic name
                       0x00, 0x21, //message ID
                       1, 2, 3 ]; //1st part of payload

    stream ~= bytes1;
    stream.handleMessages(server, connection);
    connection.payloads.shouldBeEmpty;

    ubyte[] bytes2 = [ 4, 5, 6, 7, 8]; //2nd part of payload
    stream ~= bytes2;
    stream.handleMessages(server, connection);
    connection.payloads.shouldEqual([[1, 2, 3, 4, 5, 7, 8]]);
}


void testTwoMqttInThreePackets() {
    ubyte[] bytes1 = [ 0x3c, 0x0f, //fixed header
                       0x00, 0x03, 't', 'o', 'p', //topic name
                       0x00, 0x21, //message ID
                       'a', 'b', 'c' ]; //1st part of payload
    auto stream = MqttStream(128);
    stream ~= bytes1;
    shouldBeFalse(stream.hasMessages());

    ubyte[] bytes2 = [ 'd', 'e', 'f', 'g', 'h']; //2nd part of payload
    stream ~= bytes2;
    shouldBeTrue(stream.hasMessages());
    stream.popNextMessageBytes.shouldEqual(bytes1 ~ bytes2);

    ubyte[] bytes3 = [0xe0, 0x00];
    stream ~= bytes3;
    stream.hasMessages.shouldBeTrue;
    stream.popNextMessageBytes.shouldEqual(bytes3);
}


void testTwoMqttInThreePacketsMultiPop() {
    ubyte[] bytes1 = [ 0x3c, 0x0f, //fixed header
                       0x00, 0x03, 't', 'o', 'p', //topic name
                       0x00, 0x21, //message ID
                       'a', 'b', 'c' ]; //1st part of payload
    auto stream = MqttStream(128);
    stream ~= bytes1;

    ubyte[] bytes2 = [ 'd', 'e', 'f', 'g', 'h']; //2nd part of payload
    stream ~= bytes2;

    ubyte[] bytes3 = [0xe0, 0x00];
    stream ~= bytes3;

    stream.popNextMessageBytes.shouldEqual(bytes1 ~ bytes2);
    stream.popNextMessageBytes.shouldEqual(bytes3);
}


void testTwoMqttInOnePacket() {
   auto stream = MqttStream(128);
   shouldBeFalse(stream.hasMessages());

   ubyte[] bytes1 = [ 0x3c ]; // half of header
   ubyte[] bytes2 = [ 0x0f, //2nd half fixed header
                     0x00, 0x03, 't', 'o', 'p', //topic name
                     0x00, 0x21, //message ID
                     'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', //payload
                     0xe0, 0x00, //header for disconnect
       ];
   stream ~= bytes1;
   shouldBeFalse(stream.hasMessages());

   stream ~= bytes2;
   shouldBeTrue(stream.hasMessages());
   stream.popNextMessageBytes.shouldEqual((bytes1 ~ bytes2)[0 .. $-2]);
   stream.popNextMessageBytes.shouldEqual([0xe0, 0x00]);
}


void testBug1() {
    auto stream = MqttStream(128);

    ubyte[] msg = [48, 20, 0, 16, 112, 105, 110, 103, 116, 101, 115, 116, 47, 48, 47, 114, 101, 112, 108, 121, 111, 107];
    ubyte[] bytes1 = msg ~ msg[0..$-4];
    stream ~= bytes1;
    stream.popNextMessageBytes.shouldEqual(msg);
}


void testBug2() {
    auto stream = MqttStream(128);

    ubyte[] bytes1 = [48, 26, 0, 18, 112, 105, 110, 103, 116, 101, 115, 116, 47, 48, 47, 114, 101, 113, 117, 101, 115, 116];
    stream ~= bytes1;
    stream.hasMessages.shouldBeFalse;

    ubyte[] bytes2 = [112, 105, 110, 103, 32, 48];
    stream ~= bytes2;
    stream.hasMessages.shouldBeTrue;
    stream.popNextMessageBytes.shouldEqual(bytes1 ~ bytes2);
}
