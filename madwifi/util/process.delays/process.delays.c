
#include<stdio.h>
#include<stdlib.h> // for malloc()

// #define P_SIZE 140	// voice packet size (output of bf->bf_skb->size in dmesg)
			// 140 for 80byte, 1060 for 1000byte and 1530 for 1470byte
#define T_MIN 100 	// start at 100 to save some space (292 theoretical min)
#define M_BIN_NUM 10000  // Number of bins
#define BIN_DIV	10	// Increment for the bin size
// #define REAL_P_SIZE 80  // Real size of packet (data only, no headers)
			// 80 for voice, 1000 or 1470 for the data packets
// #define WRAP_32BIT_NUM 268435456 // 28bit tsf ?

FILE *f_input, *f_out, *f_out_dist, *f_average, *f_out_percent;

// Data structure for storing start and end times ids

typedef struct{
	int s_id;
	int e_id;
	int e_size;	
	double s_usec;
	double e_usec;
    int retries;
    int rate;
}data_line;

int main(int argc, char *argv[])
{
int num_sta=0;
double run_time=0, start_time=0;
char *in_file, *out_file, *ave_file, *dist_file, *percent_file;
int total_num_packets=0, wrap_counter=0;
//int s_sec, s_usec, e_sec, e_usec;
int i=0, j=0;
data_line current, last;
int min_delay=-1; //min delay,  for comparsion to theoretical min. =99! NOT = 0!!
int data_bin[M_BIN_NUM][3], bin_num=0, median=-1; //for getting median
double pop_temp=0, percent_temp=0; //Dummy variables for calculations
double percentage=0; //For percentage distribution calculation
double delay=0, throughput=0, service_average=0, queuing_average=0;
int p_size, real_p_size;
int qt=0, qd=0, status=0, rssi=0; //dummy variables for fscanf

	/*
	 * File management
	 */ 
	if(argc != 8){
		printf("%s: <f_input> <f_out> <f_average> <f_dist> <f_percent> <num sta> <p_size>\n", argv[0]);
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
	//num_sta is a dummy variable used it index the results
	//it is not used to calculate anything.
	real_p_size = atoi(argv[7]);
	//p_size = real_p_size + 60;
	p_size = real_p_size;


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
	last.s_id = -1;
	last.e_id = -1;	
	service_average = 0;
	queuing_average = 0;
	min_delay = -1;
	total_num_packets=0;
    /*
     * Format has changed 
     * IS_TIME driver update prints out in the following format
     * HWSQN(d), Current TIME(u), Total Queued(d), Queuing TIME(u), P Buffer size(d), Status(d), Rate(d), Queue depth(u), retries(d), RSSI(d)
     * 
     */ 
	while(
/*
	fscanf(f_input, "%d\t%d\t%d\t%d\t%d\t%d\t%d\n", 
		&current.s_id, &s_sec, &s_usec,
		&current.e_id, &e_sec, &e_usec, 
		&current.e_size)  == 7 
*/
	fscanf(f_input, "%d\t%lf\t%d\t%lf\t%d\t%d\t%d\t%u\t%d\t%d\n", 
		&current.s_id, &current.e_usec, &qt,
		&current.s_usec,  &current.e_size, &status, 
        &current.rate, &qd, &current.retries, &rssi)  >= 9
	){
		// work out times in usec
		/*
		current.s_usec = s_usec + 1000000.0*s_sec;
		current.e_usec = e_usec + 1000000.0*e_sec;
		*/
        /*
	printf("%u\t%lf\t%d\t%lf\t%d\t%d\t%d\t%u\t%d\t%d\n", 
		current.s_id, current.e_usec, qt,
		current.s_usec,  current.e_size, status, 
        rate, qd, retries, rssi);
		*/
		//Exclude first time through
		if(last.s_id != -1){
			// get service time
			if(current.s_usec >= last.e_usec){
				delay = current.e_usec - current.s_usec;
			}
			// fi-1 is greater
			else{
				delay = current.e_usec - last.e_usec;
			}
			//Only update values if correct packet size
			//here we ignore other packets
			/*
			if(current.e_size == p_size){
            */
				if(delay < min_delay || min_delay == -1){
					min_delay = delay;
				}
				service_average += delay;
				queuing_average += current.e_usec - current.s_usec;
                printf("%lf\t%lf\t%lf\n", current.s_usec, current.e_usec, queuing_average);
				total_num_packets++;
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
				fprintf(f_out, "%d\t%lf\t%lf\t%d\t%d\t%d\n",
						current.s_id, current.e_usec-current.s_usec,
						delay, current.e_size, current.retries,
                        current.rate);
				
			//}
			
		}
		//first run, record the start time (end time will be left in last.e_usec)
		else{
			start_time = current.s_usec;
			//printf("Start:%f\t", start_time);
		}

        /*
        * Wraps
        * 
        if(current.e_usec < last.s_usec){
            wrap_counter++;
        }   
        */ 
		// Copy current into last and loop again
		last.s_id = current.s_id;
		last.e_id = current.e_id;
		last.e_size = current.e_size;
		last.s_usec = current.s_usec;
		last.e_usec = current.e_usec;
		last.retries = current.retries;
	}
	// work out averages
	service_average = service_average/(float)total_num_packets;
	queuing_average = queuing_average/(float)total_num_packets;
	run_time = last.e_usec - start_time;
    //run_time += wrap_counter * WRAP_32BIT_NUM;
	// this gives packets/usecond !
	throughput = total_num_packets/run_time;
	throughput *= 1000000; // for seconds
	printf("Start:%f\tEnd:%f\tRun_time:%f\n", start_time, last.e_usec, run_time);
	printf("Run time:%f\tPackets:%d\tThroughput:%f\n", run_time, total_num_packets, throughput);
	
		
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
	 * Output to average file
	 */ 
	fprintf(f_average,"%d\t%f\t%f\t%d\t%d\t%d\t%f\t", 
			num_sta, service_average, queuing_average, median, 
			min_delay, total_num_packets, throughput);
	// Output throughput in Kbits/second (should be = 64Kb/s, for 80 byte packets)
	throughput *= (8*(float)real_p_size)/1000;
	printf("Throughput:%f Kb/s\n", throughput);
	fprintf(f_average,"%f\n", throughput);

	
	
	// print out distribution of values
	// format: bin num (i), MAX bin value, AVE bin value, Number in bin
	for(i=0; i<M_BIN_NUM; i++){
		fprintf(f_out_dist,"%d\t%d\t%d\t%d\n", i, data_bin[i][0], data_bin[i][2], data_bin[i][1]);
	}

	printf("Num:%d\tAve:%f\tCrude Ave:%f\tMedian:%d\n", 
			num_sta, service_average, queuing_average, median);
	
	
fclose(f_input);
fclose(f_average);
fclose(f_out);
fclose(f_out_dist);
fclose(f_out_percent);
exit(0);
}

