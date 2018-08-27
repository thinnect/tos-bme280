/**
 * @author Raido Pahtma
 * @license MIT
 **/
generic module BME280SensorsP(uint8_t client_count) {
	provides {
		interface Init;
		interface Read<float> as Temperature[uint8_t client];
		interface Read<float> as Humidity[uint8_t client];
		interface Read<float> as Pressure[uint8_t client];
	}
	uses {
		interface Read<float> as ReadTemperature;
		interface Read<float> as ReadHumidity;
		interface Read<float> as ReadPressure;
	}
}
implementation {

	typedef struct sensor_client {
		bool temperature: 1;
		bool humidity: 1;
		bool pressure: 1;
	} sensor_client_t;

	sensor_client_t clients[client_count];

	bool temperature = FALSE;
	bool humidity = FALSE;
	bool pressure = FALSE;

	command error_t Init.init() {
		uint8_t i;
		for(i=0;i<client_count;i++) {
			clients[i].temperature = FALSE;
			clients[i].humidity = FALSE;
			clients[i].pressure = FALSE;
		}
		return SUCCESS;
	}

	command error_t Temperature.read[uint8_t client]() {
		if(clients[client].temperature) {
			return EALREADY;
		}
		if(temperature == FALSE) {
			error_t err = call ReadTemperature.read();
			if(err != SUCCESS) {
				return err;
			}
			temperature = TRUE;
		}
		clients[client].temperature = TRUE;
		return SUCCESS;
	}

	event void ReadTemperature.readDone(error_t result, float value) {
		uint8_t i;
		temperature = FALSE;
		for(i=0;i<client_count;i++) {
			if(clients[i].temperature) {
				clients[i].temperature = FALSE;
				signal Temperature.readDone[i](result, value);
			}
		}
	}

	command error_t Humidity.read[uint8_t client]() {
		if(clients[client].humidity) {
			return EALREADY;
		}
		if(humidity == FALSE) {
			error_t err = call ReadHumidity.read();
			if(err != SUCCESS) {
				return err;
			}
			humidity = TRUE;
		}
		clients[client].humidity = TRUE;
		return SUCCESS;
	}

	event void ReadHumidity.readDone(error_t result, float value) {
		uint8_t i;
		humidity = FALSE;
		for(i=0;i<client_count;i++) {
			if(clients[i].humidity) {
				clients[i].humidity = FALSE;
				signal Humidity.readDone[i](result, value);
			}
		}
	}

	command error_t Pressure.read[uint8_t client]() {
		if(clients[client].pressure) {
			return EALREADY;
		}
		if(pressure == FALSE) {
			error_t err = call ReadPressure.read();
			if(err != SUCCESS) {
				return err;
			}
			pressure = TRUE;
		}
		clients[client].pressure = TRUE;
		return SUCCESS;
	}

	event void ReadPressure.readDone(error_t result, float value) {
		uint8_t i;
		pressure = FALSE;
		for(i=0;i<client_count;i++) {
			if(clients[i].pressure) {
				clients[i].pressure = FALSE;
				signal Pressure.readDone[i](result, value);
			}
		}
	}

	default event void Temperature.readDone[uint8_t client](error_t result, float value) { }
	default event void Humidity.readDone[uint8_t client](error_t result, float value) { }
	default event void Pressure.readDone[uint8_t client](error_t result, float value) { }

}
