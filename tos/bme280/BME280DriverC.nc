/**
 * @author Raido Pahtma
 * @license MIT
 **/
#include "bme280_defs.h"
configuration BME280DriverC {
	provides {
		interface SplitControl;
		interface Read<float> as Temperature;
		interface Read<float> as Humidity;
		interface Read<float> as Pressure;
	}
}
implementation {

	#ifndef BME280_I2C_ADDRESS
	#warning BME280_I2C_ADDRESS not defined, using BME280_I2C_ADDR_PRIM
	#define BME280_I2C_ADDRESS BME280_I2C_ADDR_PRIM
	#endif//BME280_I2C_ADDRESS

	components new BME280DriverP(BME280_I2C_ADDRESS) as Sensor;
	SplitControl = Sensor;
	Temperature = Sensor.Temperature;
	Humidity = Sensor.Humidity;
	Pressure = Sensor.Pressure;

	components new Atm128I2CMasterC();
	Sensor.Resource -> Atm128I2CMasterC;
	Sensor.I2C -> Atm128I2CMasterC;

	components HplAtm128I2CBusC;
	Sensor.HplI2C -> HplAtm128I2CBusC.I2C;

	components new TimerMilliC() as Timer;
	Sensor.Timer -> Timer;

	components BusyWaitMicroC;
	Sensor.BusyWait -> BusyWaitMicroC;

}
