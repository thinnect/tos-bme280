/**
 * @author Raido Pahtma
 * @license MIT
 **/
configuration BME280SensorsC {
	provides {
		interface Read<float> as Temperature[uint8_t client];
		interface Read<float> as Humidity[uint8_t client];
		interface Read<float> as Pressure[uint8_t client];
	}
}
implementation {

	components new BME280SensorsP(uniqueCount("BME280SensorC"));
	Temperature = BME280SensorsP.Temperature;
	Humidity = BME280SensorsP.Humidity;
	Pressure = BME280SensorsP.Pressure;

	components MainC;
	MainC.SoftwareInit -> BME280SensorsP.Init;

	components BME280DriverC;
	BME280SensorsP.ReadTemperature -> BME280DriverC.Temperature;
	BME280SensorsP.ReadHumidity -> BME280DriverC.Humidity;
	BME280SensorsP.ReadPressure -> BME280DriverC.Pressure;

}
