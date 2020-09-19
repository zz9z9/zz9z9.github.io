// https://programmers.co.kr/learn/courses/30/lessons/42587

import java.util.Iterator;
import java.util.LinkedList;
import java.util.Queue;

class Solution {
     public int solution(int[] priorities, int location) {
        int printOrder = 1;
        int[] answerMap = new int[priorities.length];

        Queue<int[]> q = new LinkedList<int[]>();

        for(int i=0; i<priorities.length; i++) {
            q.add(new int[]{i, priorities[i]});
        }

        while(!q.isEmpty()) {
            int headIdx = q.peek()[0];
            int headPriority = q.peek()[1];
            Iterator<int[]> iter = q.iterator();

            while(iter.hasNext()) {
                int priority = iter.next()[1];

                if(priority > headPriority) {
                    q.add(q.poll());
                    break;
                }

                if(!iter.hasNext()) {
                    answerMap[headIdx] = printOrder;
                    q.poll();
                    printOrder++;
                }
             }
        }

        return answerMap[location];
    }
}
