
#include<stdio.h>
#include<stdlib.h> // for atoi()

// #define P_SIZE 140	// voice packet size (output of bf->bf_skb->size in dmesg)
			// 140 for 80byte, 1060 for 1000byte and 1530 for 1470byte
#define T_MIN 200 	// start at 100 to save some space (292 theoretical min)
#define M_BIN_NUM 10000  // Number of bins
#define BIN_DIV	10	// Increment for the bin size
#define WRAP_TIME	4294967295	// size of 2^32-1 for wrap around time
// #define REAL_P_SIZE 80  // Real size of packet (data only, no headers)
			// 80 for voice, 1000 or 1470 for the data packets


FILE *f_input, *f_out, *f_out_dist, *f_average, *f_out_percent;

// Data structure for storing start and end times ids


typedef struct{
	int id;                   // Hardware ID
	unsigned int return_t_usec;     // timestamp after ACK or dropped for excessive retries
    int total_queued;               // total packets ever queued
	unsigned int queuing_t_usec;    // unsigned timestamps
	int packet_size;	        // size of the packet buffer (packet + driver stuff...)
	int status;               // status of packet, 0= sucessful TX, 1= dropped
	int ratecode;             // ratecode for rate packet was sent at
    int queue_depth;                // number of packets
	int lretry;               // number of (long) retries
    int rssi;                 // RSSI of recieved ACK
}data_line;

int main(int argc, char *argv[])
{
int num_sta=0;
double run_time=0., start_time=0. ,last_wrap_time=0.;
char *in_file, *out_file, *ave_file, *dist_file, *percent_file;
int total_num_packets=0;
int i=0, j=0;
data_line current, last;
int min_delay=-1; //min delay,  for comparsion to theoretical min. =99! NOT = 0!!
int data_bin[M_BIN_NUM][3], bin_num=0, median=-1; //for getting median
double pop_temp=0., percent_temp=0.; //Dummy variables for calculations
double percentage=0.; //For percentage distribution calculation
double delay=0., throughput=0., service_average=0., queue_average=0., col_prob=0.;
int p_size, real_p_size, total_l_retries=0, time_wrap_counter=0;
int desired_ratecode=-1; //can pick packets via rate code

	/*
	 * File management
	 */ 
	if(argc != 8){
		printf("%s: <f_input> <f_out> <f_average> <f_dist> <f_percent> <num sta> <rate_code>\n", argv[0]);
		exit(1);
	}
	//Files
	in_file = argv[1];
	out_file = argv[2];
	ave_file = argv[3];
	dist_file = argv[4];
	percent_file =argv[5];
	//Variables
	num_sta = atoi(argv[6]);
	//real_p_size = atoi(argv[7]);
	desired_ratecode = atoi(argv[7]);
    
	f_input = fopen(in_file,"r");
	f_out = fopen(out_file, "w");
	f_average = fopen(ave_file, "a"); //append to this file
	f_out_dist = fopen(dist_file, "w"); 
	f_out_percent = fopen(percent_file, "w"); 

	/*
	 * Loop to set up bins for the data (from old version
	 * Start at 110 (T_MIN) and increase in 10s to M_BIN_NUM
	 */ 
	for(i=0;i<M_BIN_NUM;i++){
		
		data_bin[i][0] = T_MIN + (i+1)*10; // Max delay for bin
		data_bin[i][1] = 0; // number of packets in bin
		data_bin[i][2] = 0; // diffs from max, for average, more accurate bin value
	}
	
	
	/*
	 * Main loop
	 * Here we store 2 lines of data, calculate delays and
	 * populate the bins. Averages are left until afterwards
	 */ 
	last.id = -1;
	last.id = -1;	
	service_average = 0;
	queue_average = 0;
	min_delay = -1;
	total_num_packets=0;
	time_wrap_counter=0;
	while(
	fscanf(f_input, "%d\t%u\t%d\t%u\t%d\t%d\t%d\t%u\t%d\t%d\n", 
		&current.id, &current.return_t_usec, &current.total_queued,
		&current.queuing_t_usec,  &current.packet_size, &current.status, 
        &current.ratecode, &current.queue_depth, &current.lretry, &current.rssi
        )  >= 10
	){
		//Exclude first time through
		if(last.id != -1){
			// get service time
			if(current.queuing_t_usec >= last.return_t_usec){
				delay = current.return_t_usec - current.queuing_t_usec;
			}
			// fi-1 is greater
			else{
				delay = current.return_t_usec - last.return_t_usec;
			}
			/*
            * Print out stats for packets sent at a particular rate (24 == 11Mbps)
            * If desired_ratecode == 0, print out stats for all  packets.
            */ 
			if(current.ratecode == desired_ratecode || desired_ratecode == 0 ){
				if(delay < min_delay || min_delay == -1){
					min_delay = delay;
				}
				service_average += delay;
				queue_average += current.return_t_usec - current.queuing_t_usec;
				//Only add successfully transmitted packets
				//total_num_packets == successfully transmitted 
				//packets. 
				if(current.status == 0)
					total_num_packets++;
				//include failed packets here though
				total_l_retries += current.lretry;
				//add to appropriate bin
				//New median bit, increment j until delay is less than
				//max bin value, then add one to that bin
				//Also, calculate and record diff from max value, for averages later
				while(delay > data_bin[j][0] && j < M_BIN_NUM){
					j++;
				}
				data_bin[j][2] += data_bin[j][0] - delay; //remember diff for later
				data_bin[j][1]++;
				j=0;
				// Output to f_out file
				fprintf(f_out, "%d\t%lf\t",
						current.id, delay);
				delay = current.return_t_usec - current.queuing_t_usec;
				fprintf(f_out, "%lf\t%d\t%d\n",
						delay,
						current.lretry, current.packet_size);
			} // packet size if() statement
		}
		//first run, record the start time (end time will be left in last.return_t_usec)
		else{
			start_time = current.queuing_t_usec;
			last_wrap_time = current.queuing_t_usec;
			//printf("Start:%f\t", start_time);
		}
		// Need to watch for wrap around time for long runs! >4000 seconds
		if(current.queuing_t_usec < last_wrap_time){
			last_wrap_time = current.queuing_t_usec;
			time_wrap_counter++;
		}

		// Copy current into last and loop again
		// last = current; // ?
		last.id = current.id;
		last.return_t_usec = current.return_t_usec;
		last.total_queued = current.total_queued;
		last.queuing_t_usec = current.queuing_t_usec;
		last.packet_size = current.packet_size;
		last.status = current.status;
		last.ratecode = current.ratecode;
		last.queue_depth = current.queue_depth;
		last.lretry = current.lretry;
		last.rssi = current.rssi;
	}
	//printf("End:%f\n", last.return_t_usec);
	// work out averages
	service_average = service_average/(float)total_num_packets;
	queue_average = queue_average/(float)total_num_packets;
	run_time = last.return_t_usec - start_time; // this doesn't account for wraps.
	printf("Unadjusted RTIME:%f\t", run_time);
	run_time += (double)time_wrap_counter * WRAP_TIME;
	// this gives packets/usecond !
	throughput = total_num_packets/run_time;
	throughput *= 1000000; // for seconds
	col_prob = total_l_retries + total_num_packets;
	col_prob = total_l_retries / col_prob;
	//col_prob = total_num_packets + total_l_retries;
	printf("Run_time(sec):%f\tWraps:%d\n", run_time/1000000, time_wrap_counter);
	printf("Packets:%d\tThroughput(pps):%f\tP(col):%f\n", 
			total_num_packets, throughput, col_prob);
	
		
	/*
	 * Loop for Bin stuff
	 */ 
	
	j=0;
	bin_num =0;
	pop_temp=data_bin[0][1]; 
	percent_temp=0;
	while(j < M_BIN_NUM){
		if(data_bin[j][1] != 0){
			data_bin[j][2] = (float)data_bin[j][2]/(float)data_bin[j][1]; //get average diff
			data_bin[j][2] = data_bin[j][0] - data_bin[j][2]; // max - average diff
		}
		//if bin was empty, then use max value (for plotting data points)
		else{
			data_bin[j][2] = data_bin[j][0];
		}
		//printf("%d\t%d\t%d\n", data_bin[j][0], data_bin[j][1], data_bin[j][2]);
		// Check for most populous bin ,(skip first bin)
		if(j == 0){
			pop_temp = data_bin[j][1];
		}
		else{
			if(data_bin[j][1] > pop_temp){
				bin_num = j;
				pop_temp = data_bin[j][1];
			}
		}	
		// Work out percentages
		if(data_bin[j][1] !=0 ){
			percent_temp += data_bin[j][1];
			percentage = 100*(float)percent_temp/(float)total_num_packets;
			fprintf(f_out_percent,"%f\t%d\t%f\t%d\n", percentage, data_bin[j][2], percent_temp, j);
		}
		
		j++;
	}

	median = data_bin[bin_num][2]; // Want the (average for bin) delay value 

	/*
	 * Out put to average file
	 */ 
	fprintf(f_average,"%d\t%f\t%f\t%d\t%d\t%d\t%f\t", 
			num_sta, service_average, queue_average, median, 
			min_delay, total_num_packets, throughput);
	// Output throughput in Kbits/second (should be = 64Kb/s, for 80 byte packets/100pps)
	throughput *= (8*(float)real_p_size)/1000;
	//throughput *= (8*(float)real_p_size)/1024;
	printf("Throughput:%f Kb/s\n", throughput);
	fprintf(f_average,"%f\t%f\n", throughput, col_prob);

	// print out distribution of values
	// format: bin num (i), MAX bin value, AVE bin value, Number in bin
	for(i=0; i<M_BIN_NUM; i++){
		fprintf(f_out_dist,"%d\t%d\t%d\t%d\n", i, data_bin[i][0], data_bin[i][2], data_bin[i][1]);
	}

	printf("Num:%d\tAve:%f\tCrude Ave:%f\tMedian:%d\n", 
			num_sta, service_average, queue_average, median);
	
	
// close all the files
	
fclose(f_input);
fclose(f_average);
fclose(f_out);
fclose(f_out_dist);
fclose(f_out_percent);
exit(0);
}

