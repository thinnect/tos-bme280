/**
 * @author Raido Pahtma
 * @license MIT
 **/
generic configuration BME280SensorC() {
	provides {
		interface Read<float> as Temperature;
		interface Read<float> as Humidity;
		interface Read<float> as Pressure;
	}
}
implementation {

	enum {
		BME280_SENSOR_CLIENT = unique("BME280SensorC")
	};

	components BME280SensorsC;
	Temperature = BME280SensorsC.Temperature[BME280_SENSOR_CLIENT];
	Humidity = BME280SensorsC.Humidity[BME280_SENSOR_CLIENT];
	Pressure = BME280SensorsC.Pressure[BME280_SENSOR_CLIENT];

}
