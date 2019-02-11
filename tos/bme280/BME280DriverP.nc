/**
 * @author Raido Pahtma
 * @license MIT
 **/
#include "bme280.h"
#include "bme280.c"
generic module BME280DriverP(uint8_t bme_i2c_addr) {
	provides {
		interface SplitControl;
		interface Read<float> as Temperature;
		interface Read<float> as Pressure;
		interface Read<float> as Humidity;
	}
	uses {
		interface Timer<TMilli>;
		interface Resource;
		interface I2CPacket<TI2CBasicAddr> as I2C;

		interface HplAtm128I2CBus as HplI2C;
		interface BusyWait<TMicro,uint16_t>;
	}
}
implementation {

	#define __MODUUL__ "bme"
	#define __LOG_LEVEL__ ( LOG_LEVEL_BME280DriverP & BASE_LOG_LEVEL )
	#include "log.h"

	enum BMEDriverStates {
		STM_OFF,
		STM_STOPPING,
		STM_STARTING,
		STM_CHECK,
		STM_CHECK_READ,
		STM_INIT,
		STM_SETTINGS,
		STM_IDLE,
		STM_FORCE,
		STM_READ
	};

	typedef struct bme_driver {
		uint8_t state    : 4;
		bool temperature : 1;
		bool pressure    : 1;
		bool humidity    : 1;
	} bme_driver_t;

	bme_driver_t m = { STM_OFF, FALSE, FALSE, FALSE };

	uint8_t m_chip_id = 0;

	struct bme280_dev dev;

	void user_delay_ms(uint32_t period);
	int8_t user_i2c_read(uint8_t dev_id, uint8_t reg_addr, uint8_t *reg_data, uint16_t len);
	int8_t user_i2c_write(uint8_t dev_id, uint8_t reg_addr, uint8_t *reg_data, uint16_t len);

	task void stm();

	event void Resource.granted() {
		debug1("g %x", bme_i2c_addr);
		post stm();
	}

	void startFailure(int line) {
		err1("fail %d", line);
		m.state = STM_OFF;
		call Resource.release();
		signal SplitControl.startDone(FAIL);
	}

	task void stm_failure() {
		startFailure(__LINE__);
	}

	void signalReadFailure() {
		if(m.temperature) {
			m.temperature = FALSE;
			signal Temperature.readDone(FAIL, 0);
		}
		if(m.humidity) {
			m.humidity = FALSE;
			signal Humidity.readDone(FAIL, 0);
		}
		if(m.pressure) {
			m.pressure = FALSE;
			signal Pressure.readDone(FAIL, 0);
		}
	}

	task void stm() {
		switch(m.state) {
			case STM_STARTING: {
				if(call Resource.isOwner()) {
					error_t err = call I2C.write(I2C_START, bme_i2c_addr, 1, (uint8_t *)"\xD0");
					debug1("w=%d", err);
					if(err == SUCCESS) {
						m.state = STM_CHECK;
					}
					else startFailure(__LINE__);
				}
				else {
					error_t err = call Resource.request();
					if(err != SUCCESS) {
						startFailure(__LINE__);
					}
				}
			}
			break;
			case STM_CHECK: {
				error_t err = call I2C.read(I2C_START | I2C_STOP, bme_i2c_addr, sizeof(m_chip_id), &m_chip_id);
				debug1("r=%d", err);
				if(err == SUCCESS) {
					m.state = STM_INIT;
				}
				else startFailure(__LINE__);
			}
			break;
			case STM_INIT: {
				debug1("BME280: %02X", m_chip_id);

				if(m_chip_id == BME280_CHIP_ID) {
					int8_t rslt;

					dev.dev_id = bme_i2c_addr; // BME280_I2C_ADDR_PRIM or BME280_I2C_ADDR_SEC
					dev.intf = BME280_I2C_INTF;
					dev.read = user_i2c_read;
					dev.write = user_i2c_write;
					dev.delay_ms = user_delay_ms;

					rslt = bme280_init(&dev);
					debug1("i=%d", rslt);
					if(rslt == BME280_OK) {
						m.state = STM_SETTINGS;
						post stm();
					}
					else startFailure(__LINE__);
				}
				else startFailure(__LINE__);
			}
			break;
			case STM_SETTINGS: {
				int8_t rslt;

				rslt = bme280_soft_reset(&dev);
				if(rslt == BME280_OK) {
					dev.settings.osr_h = BME280_OVERSAMPLING_4X;
					dev.settings.osr_p = BME280_OVERSAMPLING_4X;
					dev.settings.osr_t = BME280_OVERSAMPLING_4X;
					dev.settings.filter = BME280_FILTER_COEFF_OFF;

					rslt = bme280_set_sensor_settings(BME280_OSR_PRESS_SEL | BME280_OSR_TEMP_SEL | BME280_OSR_HUM_SEL | BME280_FILTER_SEL, &dev);
					debug1("set=%d", rslt);

					if(rslt == BME280_OK) {
						call Resource.release();
						m.state = STM_IDLE;
						signal SplitControl.startDone(SUCCESS);
					}
					else startFailure(__LINE__);
				}
				else startFailure(__LINE__);
			}
			break;
			case STM_FORCE: {
				int8_t rslt = bme280_set_sensor_mode(BME280_FORCED_MODE, &dev);
				debug1("frc=%d", rslt);
				if(rslt == BME280_OK) {
					m.state = STM_READ;
					call Timer.startOneShot(40);
				}
				else {
					m.state = STM_IDLE;
					signalReadFailure();
				}
			}
			break;
			case STM_READ: {
				struct bme280_data comp_data = {0, 0, 0};
				int8_t rslt = bme280_get_sensor_data(BME280_ALL, &comp_data, &dev);
				debug1("gsd %"PRIu32" %"PRIi32" %"PRIu32, comp_data.pressure/100, comp_data.temperature/100, comp_data.humidity/1024UL);

				m.state = STM_IDLE;
				call Resource.release();

				if(rslt == BME280_OK) {
					if(m.temperature) {
						m.temperature = FALSE;
						signal Temperature.readDone(SUCCESS, comp_data.temperature/100.0);
					}
					if(m.humidity) {
						m.humidity = FALSE;
						signal Humidity.readDone(SUCCESS, comp_data.humidity/1024.0);
					}
					if(m.pressure) {
						m.pressure = FALSE;
						signal Pressure.readDone(SUCCESS, comp_data.pressure/100.0);
					}
				}
				else {
					signalReadFailure();
				}
			}
			break;
			case STM_IDLE: {
				call Resource.request();
				m.state = STM_FORCE;
			}
			break;
		}
	}

	event void Timer.fired() {
		post stm();
	}

	command error_t SplitControl.start() {
		m.state = STM_STARTING;
		post stm();
		return SUCCESS;
	}

	task void stopDone() {
		call Resource.release();
		m.state = STM_OFF;
		signal SplitControl.stopDone(SUCCESS);
	}

	command error_t SplitControl.stop() {
		if(m.state == STM_IDLE) {
			m.state = STM_STOPPING;
			post stopDone();
			return SUCCESS;
		}
		return EBUSY;
	}

	command error_t Temperature.read() {
		if(m.state < STM_IDLE) {
			return EOFF;
		}
		if(m.temperature) {
			return EBUSY;
		}
		m.temperature = TRUE;
		if(m.state == STM_IDLE) {
			post stm();
		}
		return SUCCESS;
	}

	command error_t Pressure.read() {
		if(m.state < STM_IDLE) {
			return EOFF;
		}
		if(m.pressure) {
			return EBUSY;
		}
		m.pressure = TRUE;
		if(m.state == STM_IDLE) {
			post stm();
		}
		return SUCCESS;
	}

	command error_t Humidity.read() {
		if(m.state < STM_IDLE) {
			return EOFF;
		}
		if(m.humidity) {
			return EBUSY;
		}
		m.humidity = TRUE;
		if(m.state == STM_IDLE) {
			post stm();
		}
		return SUCCESS;
	}

	async event void I2C.readDone(error_t error, uint16_t addr, uint8_t length, uint8_t *data) {
		if(error == SUCCESS) {
			post stm();
		}
		else {
			post stm_failure();
		}
	}

	async event void I2C.writeDone(error_t error, uint16_t addr, uint8_t length, uint8_t *data) {
		if(error == SUCCESS) {
			post stm();
		}
		else {
			post stm_failure();
		}
	}

	async event void HplI2C.commandComplete() {
		//atomic debug1("HplI2C.cC");
	}

	void user_delay_ms(uint32_t period) {
		/*
		 * Return control or wait,
		 * for a period amount of milliseconds
		 */
		 debug1("delay %"PRIu32, period);
		 for(;period>0;period--) {
			call BusyWait.wait(1000);
		 }
	}

	int8_t user_i2c_read(uint8_t dev_id, uint8_t reg_addr, uint8_t *reg_data, uint16_t len) {
		int8_t rslt = 0; /* Return 0 for Success, non-zero for failure */
		/*
		 * |------------+---------------------|
		 * | I2C action | Data                |
		 * |------------+---------------------|
		 * | Start      | -                   |
		 * | Write      | (reg_addr)          |
		 * | Stop       | -                   |
		 * | Start      | -                   |
		 * | Read       | (reg_data[0])       |
		 * | Read       | (....)              |
		 * | Read       | (reg_data[len - 1]) |
		 * | Stop       | -                   |
		 * |------------+---------------------|
		 */
		debug3("i2c_r(%02X, %02x, ..., %d)", dev_id, reg_addr, len);
		call HplI2C.init(ATM128_I2C_EXTERNAL_PULLDOWN);
		call HplI2C.readCurrent();
		call HplI2C.enable(TRUE);
		call HplI2C.setStop(FALSE);
		call HplI2C.setStart(FALSE);
		call HplI2C.enableAck(FALSE);
		call HplI2C.enableInterrupt(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		//while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.setStart(TRUE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.write(((dev_id & 0x7f) << 1) | ATM128_I2C_SLA_WRITE);
		call HplI2C.setStart(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.write(reg_addr);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.setStart(TRUE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.write(((dev_id & 0x7f) << 1) | ATM128_I2C_SLA_READ);
		call HplI2C.setStart(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		if(call HplI2C.status() == 0x40) {
			uint8_t i;
			for(i=0;i<len;i++) {
				if(i == len-1) {
					call HplI2C.enableAck(FALSE);
				}
				else {
					call HplI2C.enableAck(TRUE);
				}
				call HplI2C.setInterruptPending(TRUE);
				call HplI2C.sendCommand();
				while(!call HplI2C.isRealInterruptPending());
				debug4("r %d %02X", i, call HplI2C.status());
				reg_data[i] = call HplI2C.read();
			}
		}
		else {
			rslt = 1;
			warn4("i2c %02X", call HplI2C.status());
		}

		call HplI2C.setStop(TRUE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		// while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.enable(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		// while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		return rslt;
	}

	int8_t user_i2c_write(uint8_t dev_id, uint8_t reg_addr, uint8_t *reg_data, uint16_t len) {
		int8_t rslt = 0; /* Return 0 for Success, non-zero for failure */
		/*
		 * |------------+---------------------|
		 * | I2C action | Data                |
		 * |------------+---------------------|
		 * | Start      | -                   |
		 * | Write      | (reg_addr)          |
		 * | Write      | (reg_data[0])       |
		 * | Write      | (....)              |
		 * | Write      | (reg_data[len - 1]) |
		 * | Stop       | -                   |
		 * |------------+---------------------|
		 */
		debug3("i2c_w(%02X, %02x, ..., %d)", dev_id, reg_addr, len);
		call HplI2C.init(ATM128_I2C_EXTERNAL_PULLDOWN);
		call HplI2C.readCurrent();
		call HplI2C.enable(TRUE);
		call HplI2C.setStop(FALSE);
		call HplI2C.setStart(FALSE);
		call HplI2C.enableAck(FALSE);
		call HplI2C.enableInterrupt(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		//while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.setStart(TRUE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.write(((dev_id & 0x7f) << 1) | ATM128_I2C_SLA_WRITE);
		call HplI2C.setStart(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		if(call HplI2C.status() == 0x18) {
			call HplI2C.write(reg_addr);
			call HplI2C.setInterruptPending(TRUE);
			call HplI2C.sendCommand();
			while(!call HplI2C.isRealInterruptPending());
			debug4("%02X", call HplI2C.status());
		}
		else {
			warn4("i2c %02X", call HplI2C.status());
			rslt = 1;
		}

		if((rslt == 0) && (call HplI2C.status() == 0x28)) {
			uint8_t i;
			for(i=0;i<len;i++) {
				call HplI2C.write(reg_data[i]);
				if(i-1==len) {
					call HplI2C.enableAck(FALSE);
				}
				else {
					call HplI2C.enableAck(TRUE);
				}
				call HplI2C.setInterruptPending(TRUE);
				call HplI2C.sendCommand();
				while(!call HplI2C.isRealInterruptPending());
				debug4("w %d", i);
			}
		}
		else {
			warn4("i2c %02X", call HplI2C.status());
			rslt = 1;
		}

		call HplI2C.setStop(TRUE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		// while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		call HplI2C.enable(FALSE);
		call HplI2C.setInterruptPending(TRUE);
		call HplI2C.sendCommand();
		// while(!call HplI2C.isRealInterruptPending());
		debug4("%02X", call HplI2C.status());

		return rslt;
	}

}
